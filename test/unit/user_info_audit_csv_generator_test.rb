# frozen_string_literal: true

require_relative '../test_helper'

require 'csv'

class UserInfoAuditCsvGeneratorTest < ActiveSupport::TestCase
  Result = NysenateAuditUtils::Reporting::UserInfoAuditService::Result

  def setup
    # A minimal stand-in for Project — the generator only reads #identifier.
    @project = Struct.new(:identifier).new('testproj')
    @generated_at = Time.new(2026, 6, 9, 14, 30, 0, '+00:00')
  end

  def generate(result, dry_run: false)
    NysenateAuditUtils::Reporting::UserInfoAuditCsvGenerator.generate(
      result, project: @project, dry_run: dry_run, generated_at: @generated_at
    )
  end

  def empty_result
    Result.new(changes: [], exceptions: [], summary: {}, errors: [])
  end

  # Parse the flat CSV into rows for assertions.
  def rows(csv_string)
    CSV.parse(csv_string)
  end

  test 'header includes report name and project identifier' do
    csv = rows(generate(empty_result))

    assert_includes csv, ['Report Name', 'Account Holder Info Audit']
    assert_includes csv, ['Project', 'testproj']
  end

  test 'header reports apply mode when not a dry run' do
    csv = rows(generate(empty_result, dry_run: false))

    assert_includes csv, ['Mode', 'Apply']
  end

  test 'header reports dry run mode when dry_run is true' do
    csv = rows(generate(empty_result, dry_run: true))

    assert_includes csv, ['Mode', 'Dry run (no changes applied)']
  end

  test 'header formats generated_at timestamp' do
    csv = rows(generate(empty_result))

    generated = csv.find { |r| r[0] == 'Generated at' }
    assert_not_nil generated
    assert_equal @generated_at.strftime('%Y-%m-%d %H:%M:%S %Z'), generated[1]
  end

  test 'header includes summary counters' do
    result = Result.new(
      changes: [], exceptions: [], errors: [],
      summary: {
        tickets_scanned: 20,
        unresolved_tickets: 2,
        account_holders_checked: 7,
        pairs_with_changes: 3,
        field_updates: 5,
        tickets_updated: 4
      }
    )

    csv = rows(generate(result))

    assert_includes csv, ['Total Tickets Scanned', '20']
    assert_includes csv, ['Unresolved tickets (review needed)', '2']
    assert_includes csv, ['Total Account Holders checked', '7']
    assert_includes csv, ['Account Holders with changes', '3']
    assert_includes csv, ['Field updates', '5']
    assert_includes csv, ['Tickets updated', '4']
  end

  test 'header omits review-needed suffix when there are no unresolved tickets' do
    result = Result.new(
      changes: [], exceptions: [], errors: [],
      summary: { unresolved_tickets: 0 }
    )

    csv = rows(generate(result))

    assert_includes csv, ['Unresolved tickets', '0']
    assert_not(csv.any? { |r| r[0] == 'Unresolved tickets (review needed)' })
  end

  test 'header labels tickets-to-update for dry runs' do
    result = Result.new(
      changes: [], exceptions: [], errors: [],
      summary: { tickets_updated: 4 }
    )

    csv = rows(generate(result, dry_run: true))

    assert_includes csv, ['Tickets to update', '4']
  end

  test 'header emits one row per unresolved category' do
    result = Result.new(
      changes: [], exceptions: [], errors: [],
      summary: { unresolved_by_category: { 'user_not_found' => 2, 'data_source_error' => 1 } }
    )

    csv = rows(generate(result))

    assert_includes csv, ['Unresolved Tickets by category']
    assert_includes csv, ['user_not_found', '2']
    assert_includes csv, ['data_source_error', '1']
  end

  test 'exceptions section lists one row per affected ticket' do
    result = Result.new(
      changes: [], errors: [], summary: {},
      exceptions: [
        {
          issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: nil,
          category: 'user_not_found', message: 'No Employee found with ID 12345'
        },
        {
          issue_id: 11, subject: 'Add AIX', user_type: 'Employee', user_id: '12345',
          account_holder_name: nil,
          category: 'user_not_found', message: 'No Employee found with ID 12345'
        }
      ]
    )

    csv = rows(generate(result))

    assert_includes csv, ['Unresolved Tickets']
    assert_includes csv,
                    ['10', 'Add Oracle', 'Employee', '12345', nil,
                     'user_not_found', 'No Employee found with ID 12345']
    assert_includes csv,
                    ['11', 'Add AIX', 'Employee', '12345', nil,
                     'user_not_found', 'No Employee found with ID 12345']
  end

  test 'exceptions section renders missing-field categories' do
    result = Result.new(
      changes: [], errors: [], summary: {},
      exceptions: [
        {
          issue_id: 12, subject: 'Add SFS', user_type: '', user_id: '',
          account_holder_name: nil,
          category: 'missing_user_type_and_id',
          message: 'Account Holder Type and ID are both blank'
        }
      ]
    )

    csv = rows(generate(result))

    assert_includes csv,
                    ['12', 'Add SFS', '', '', nil,
                     'missing_user_type_and_id', 'Account Holder Type and ID are both blank']
  end

  test 'changes section renders Applied as yes or no' do
    result = Result.new(
      exceptions: [], errors: [], summary: {},
      changes: [
        {
          issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe',
          field: 'User Email', old_value: 'old@example.com', new_value: 'new@example.com',
          applied: true
        },
        {
          issue_id: 11, subject: 'Add AIX', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe',
          field: 'User Phone', old_value: '555-0000', new_value: '555-1111',
          applied: false
        }
      ]
    )

    csv = rows(generate(result))

    assert_includes csv, ['Changes']
    applied_row = csv.find { |r| r[0] == '10' }
    skipped_row = csv.find { |r| r[0] == '11' }
    assert_equal 'yes', applied_row.last
    assert_equal 'no', skipped_row.last
  end

  test 'changes section includes the Account Holder Name for each ticket row' do
    result = Result.new(
      exceptions: [], errors: [], summary: {},
      changes: [
        {
          issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe',
          field: 'User Email', old_value: 'old@example.com', new_value: 'new@example.com',
          applied: true
        }
      ]
    )

    csv = rows(generate(result))

    header = csv.find { |r| r.first == 'Issue ID' }
    name_index = header.index('Account Holder Name')
    assert_not_nil name_index, 'Changes header should include an Account Holder Name column'

    change_row = csv.find { |r| r[0] == '10' }
    assert_equal 'Jane Doe', change_row[name_index]
  end

  test 'produces well-formed section headers even when empty' do
    csv = rows(generate(empty_result))

    # Both table header rows are always present. Both column-header rows lead
    # with 'Issue ID'; the Unresolved Tickets table is distinguished by
    # 'Category' and the Changes table by 'Applied'.
    assert_includes csv, ['Unresolved Tickets']
    assert_includes csv, ['Changes']
    assert(csv.any? { |r| r.first == 'Issue ID' && r.include?('Category') })
    assert(csv.any? { |r| r.first == 'Issue ID' && r.include?('Applied') })
  end
end
