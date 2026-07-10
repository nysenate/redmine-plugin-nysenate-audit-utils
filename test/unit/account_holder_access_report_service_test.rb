# frozen_string_literal: true

require_relative '../test_helper'

class AccountHolderAccessReportServiceTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers,
           :enumerations, :custom_fields, :custom_values

  def setup
    @project = Project.find(1)
    @tracker = Tracker.find(1)

    @fields = setup_standard_bachelp_fields(@tracker)
    @user_id_field = @fields[:user_id]
    @user_name_field = @fields[:user_name]
    @user_uid_field = @fields[:user_uid]
    @account_action_field = @fields[:account_action]
    @target_system_field = @fields[:target_system]

    @closed_status = IssueStatus.where(is_closed: true).first
  end

  def teardown
    clear_audit_configuration
  end

  test 'initializes with project' do
    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    assert_equal @project, service.project
    assert_equal [], service.errors
  end

  test 'generate returns one row per active account across all systems' do
    create_closed_test_issue('11111', 'Alice Smith', 'Oracle / SFMS', 'Add', 1.day.ago)
    create_closed_test_issue('22222', 'Bob Jones', 'AIX', 'Add', 2.days.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert service.success?
    assert_equal 2, result.size
    assert_includes result.map { |r| r[:account_type] }, 'Oracle / SFMS'
    assert_includes result.map { |r| r[:account_type] }, 'AIX'
  end

  test 'generate includes inactive accounts with their status (latest action Delete)' do
    create_closed_test_issue('11111', 'Active User', 'SFS', 'Add', 2.days.ago)
    create_closed_test_issue('22222', 'Removed User', 'SFS', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    # Status filtering is the controller's job; the service surfaces both.
    assert_equal 2, result.size
    by_user = result.index_by { |r| r[:user_id] }
    assert_equal 'active', by_user['11111'][:status]
    assert_equal 'inactive', by_user['22222'][:status]
  end

  test 'generate marks account inactive when latest Add is superseded by a Delete' do
    create_closed_test_issue('11111', 'Alice', 'NYSDS', 'Add', 5.days.ago)
    create_closed_test_issue('11111', 'Alice', 'NYSDS', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert_equal 1, result.size
    assert_equal 'inactive', result.first[:status]
  end

  test 'generate includes an account on each system the holder has active' do
    create_closed_test_issue('11111', 'Alice', 'Oracle / SFMS', 'Add', 2.days.ago)
    create_closed_test_issue('11111', 'Alice', 'AIX', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert_equal 2, result.size
    assert_equal ['11111', '11111'], result.map { |r| r[:user_id] }
    assert_equal ['AIX', 'Oracle / SFMS'], result.map { |r| r[:account_type] }.sort
  end

  test 'generate orders rows by account holder name' do
    create_closed_test_issue('33333', 'Zach Last', 'SFS', 'Add', 1.day.ago)
    create_closed_test_issue('11111', 'Alice First', 'SFS', 'Add', 1.day.ago)
    create_closed_test_issue('22222', 'Mike Middle', 'SFS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert_equal ['Alice First', 'Mike Middle', 'Zach Last'], result.map { |r| r[:user_name] }
  end

  test 'generate includes the request code of the latest add ticket' do
    create_closed_test_issue('11111', 'Alice', 'Oracle / SFMS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    # 'Oracle / SFMS' => USR prefix, 'Add' => A suffix (see test helper mappings)
    assert_equal 'USRA', result.first[:request_code]
  end

  test 'generate enriches name and username from custom fields' do
    create_closed_test_issue('11111', 'Alice Smith', 'AIX', 'Add', 1.day.ago, uid: 'asmith')

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    row = result.first
    assert_equal 'Alice Smith', row[:user_name]
    assert_equal 'asmith', row[:user_uid]
  end

  test 'generate returns empty array when no accounts exist' do
    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert_equal [], result
    assert service.success?
  end

  test 'generate handles errors gracefully' do
    mock_service = mock('account_tracking_service')
    mock_service.stubs(:get_account_statuses_by_system).raises(StandardError, 'Database error')
    NysenateAuditUtils::AccountTracking::AccountTrackingService.stubs(:new).returns(mock_service)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    result = service.generate

    assert_nil result
    assert_not service.success?
    assert_match(/Report generation failed/, service.errors.first)
  end

  test 'generate row includes all expected keys' do
    create_closed_test_issue('11111', 'Alice', 'PayServ', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    row = service.generate.first

    %i[user_name user_id user_uid user_type account_type request_code status issue_id].each do |key|
      assert row.key?(key), "expected row to include #{key}"
    end
  end

  private

  def create_closed_test_issue(user_id, user_name, target_system, account_action, closed_time, uid: nil)
    custom_values = {
      @user_id_field.id => user_id.to_s,
      @target_system_field.id => target_system,
      @account_action_field.id => account_action
    }
    custom_values[@user_name_field.id] = user_name if user_name
    custom_values[@user_uid_field.id] = uid if uid

    issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Test Issue for #{user_id}",
      status: @closed_status,
      priority_id: 5,
      custom_field_values: custom_values
    )

    Issue.where(id: issue.id).update_all(closed_on: closed_time)
    issue.reload
  end
end
