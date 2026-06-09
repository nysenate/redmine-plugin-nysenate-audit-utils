# frozen_string_literal: true

require_relative '../test_helper'

class UserInfoAuditServiceTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers,
           :enumerations, :custom_fields, :custom_values

  Service = NysenateAuditUtils::Reporting::UserInfoAuditService

  # Authoritative payload a UserService lookup would return for an employee.
  AUTHORITATIVE = {
    name: 'John Doe',
    email: 'john.doe@example.com',
    phone: '555-1234',
    status: 'Active',
    uid: 'jdoe',
    location: 'Capitol'
  }.freeze

  def setup
    @project = Project.find(1)
    @tracker = Tracker.find(1)
    @fields = setup_standard_bachelp_fields(@tracker)
    @open_status = IssueStatus.where(is_closed: false).first

    # A real, logged-in journal author so apply-mode writes are attributed.
    User.current = User.find(1)
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    clear_audit_configuration
    User.current = nil
  end

  # Creates an issue with Account Holder Type/ID set and optional stale values
  # for the synced fields (keyed by the field symbol from setup_standard_bachelp_fields).
  def create_issue(user_type:, user_id:, seed: {})
    values = {
      @fields[:user_type].id => user_type,
      @fields[:user_id].id => user_id
    }
    seed.each { |field_key, value| values[@fields[field_key].id] = value }

    Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Account request for #{user_id}",
      status: @open_status,
      priority_id: 5,
      custom_field_values: values
    )
  end

  def stub_lookup(returns: AUTHORITATIVE)
    NysenateAuditUtils::Users::UserService.any_instance
                                          .stubs(:find_by_id).returns(returns)
  end

  # --- Configuration validation -------------------------------------------

  test 'run fails when account holder type/id fields are not configured' do
    clear_audit_configuration

    result = Service.new(project: @project).run

    assert_not result.success?
    assert(result.errors.any? { |e| e.include?('Account Holder Type') })
    assert(result.errors.any? { |e| e.include?('Account Holder ID') })
    assert_empty result.changes
  end

  test 'run fails when synced fields are missing' do
    # Configure only the lookup-key fields, omitting the synced fields.
    configure_audit_fields(
      user_type_field_id: @fields[:user_type].id,
      user_id_field_id: @fields[:user_id].id
    )

    result = Service.new(project: @project).run

    assert_not result.success?
    assert(result.errors.any? { |e| e.include?('Missing Account Holder custom fields') })
  end

  # --- Exception categories ------------------------------------------------

  test 'records missing_user_id exception when account holder id is blank' do
    create_issue(user_type: 'Employee', user_id: '')

    result = Service.new(project: @project).run

    assert result.success?
    assert_equal 1, result.exceptions.size
    assert_equal 'missing_user_id', result.exceptions.first[:category]
  end

  test 'records invalid_user_type exception when lookup raises ArgumentError' do
    # The lookup itself rejects the type; the stored value need not be invalid.
    create_issue(user_type: 'Employee', user_id: '12345')
    NysenateAuditUtils::Users::UserService.any_instance
                                          .stubs(:find_by_id)
                                          .raises(ArgumentError, 'Invalid user type')

    result = Service.new(project: @project).run

    assert_equal 1, result.exceptions.size
    assert_equal 'invalid_user_type', result.exceptions.first[:category]
  end

  test 'records data_source_error exception when lookup raises StandardError' do
    create_issue(user_type: 'Employee', user_id: '12345')
    NysenateAuditUtils::Users::UserService.any_instance
                                          .stubs(:find_by_id)
                                          .raises(StandardError, 'ESS down')

    result = Service.new(project: @project).run

    assert_equal 1, result.exceptions.size
    assert_equal 'data_source_error', result.exceptions.first[:category]
    assert_match(/ESS down/, result.exceptions.first[:message])
  end

  test 'records user_not_found exception when lookup returns nil' do
    create_issue(user_type: 'Employee', user_id: '99999')
    stub_lookup(returns: nil)

    result = Service.new(project: @project).run

    assert_equal 1, result.exceptions.size
    assert_equal 'user_not_found', result.exceptions.first[:category]
  end

  test 'records issue_save_failed exception when issue save fails' do
    create_issue(user_type: 'Employee', user_id: '12345', seed: { user_email: 'stale@example.com' })
    stub_lookup
    Issue.any_instance.stubs(:save).returns(false)

    result = Service.new(project: @project).run

    assert(result.exceptions.any? { |e| e[:category] == 'issue_save_failed' })
  end

  # --- Diff detection ------------------------------------------------------

  test 'detects field drift and records a change row' do
    issue = create_issue(user_type: 'Employee', user_id: '12345',
                         seed: { user_email: 'stale@example.com' })
    stub_lookup

    result = Service.new(project: @project, dry_run: true).run

    email_change = result.changes.find { |c| c[:field] == @fields[:user_email].name }
    assert_not_nil email_change
    assert_equal issue.id, email_change[:issue_id]
    assert_equal 'stale@example.com', email_change[:old_value]
    assert_equal 'john.doe@example.com', email_change[:new_value]
  end

  test 'ignores whitespace-only differences when comparing values' do
    # Seed every synced field with the authoritative value plus surrounding
    # whitespace; normalize(strip) should treat these as equal -> no changes.
    create_issue(
      user_type: 'Employee', user_id: '12345',
      seed: {
        user_name: '  John Doe  ', user_email: 'john.doe@example.com ',
        user_phone: ' 555-1234', user_status: 'Active ',
        user_uid: ' jdoe ', user_location: ' Capitol '
      }
    )
    stub_lookup

    result = Service.new(project: @project, dry_run: true).run

    assert_empty result.changes
  end

  # --- Dry run vs apply ----------------------------------------------------

  test 'dry run records changes without writing to the database' do
    issue = create_issue(user_type: 'Employee', user_id: '12345',
                         seed: { user_email: 'stale@example.com' })
    stub_lookup
    journals_before = issue.journals.count

    result = Service.new(project: @project, dry_run: true).run

    assert(result.changes.all? { |c| c[:applied] == false })
    issue.reload
    assert_equal 'stale@example.com', issue.custom_value_for(@fields[:user_email]).value
    assert_equal journals_before, issue.journals.count
  end

  test 'apply mode updates custom fields and writes a journal without notifying' do
    issue = create_issue(user_type: 'Employee', user_id: '12345',
                         seed: { user_email: 'stale@example.com' })
    stub_lookup
    # Discard the issue-creation notifications so only reconciliation mail
    # (if any) would show up below.
    ActionMailer::Base.deliveries.clear

    result = Service.new(project: @project, dry_run: false).run

    assert(result.changes.any? { |c| c[:applied] == true })
    issue.reload
    assert_equal 'john.doe@example.com', issue.custom_value_for(@fields[:user_email]).value

    journal = issue.journals.last
    assert_not_nil journal
    assert_match(/reconciled by audit_account_holder_info/, journal.notes)
    # Watcher notifications are suppressed (journal.notify = false).
    assert_empty ActionMailer::Base.deliveries
  end

  # --- Summary -------------------------------------------------------------

  test 'summary aggregates scanned pairs, changes, exceptions and field updates' do
    # Seed every synced field with the authoritative value, then make exactly
    # two stale so field_updates is unambiguously 2.
    create_issue(
      user_type: 'Employee', user_id: '12345',
      seed: {
        user_name: AUTHORITATIVE[:name], user_email: 'stale@example.com',
        user_phone: 'old', user_status: AUTHORITATIVE[:status],
        user_uid: AUTHORITATIVE[:uid], user_location: AUTHORITATIVE[:location]
      }
    )
    create_issue(user_type: 'Employee', user_id: '')

    service = Service.new(project: @project, dry_run: true)
    NysenateAuditUtils::Users::UserService.any_instance
                                          .stubs(:find_by_id).returns(AUTHORITATIVE)

    result = service.run
    summary = result.summary

    assert_equal 2, summary[:pairs_scanned]
    assert_equal 1, summary[:pairs_with_changes]
    assert_equal 1, summary[:pairs_with_exceptions]
    assert_equal 2, summary[:field_updates]
    assert_equal({ 'missing_user_id' => 1 }, summary[:exceptions_by_category])
  end
end
