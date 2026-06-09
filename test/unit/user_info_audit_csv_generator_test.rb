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
        pairs_scanned: 7,
        pairs_with_exceptions: 2,
        pairs_with_changes: 3,
        field_updates: 5
      }
    )

    csv = rows(generate(result))

    assert_includes csv, ['Account Holders scanned', '7']
    assert_includes csv, ['Account Holders with exceptions', '2']
    assert_includes csv, ['Account Holders with changes', '3']
    assert_includes csv, ['Field updates', '5']
  end

  test 'header emits one row per exception category' do
    result = Result.new(
      changes: [], exceptions: [], errors: [],
      summary: { exceptions_by_category: { 'user_not_found' => 2, 'data_source_error' => 1 } }
    )

    csv = rows(generate(result))

    assert_includes csv, ['Exceptions: user_not_found', '2']
    assert_includes csv, ['Exceptions: data_source_error', '1']
  end

  test 'exceptions section lists each exception with issue_ids joined' do
    result = Result.new(
      changes: [], errors: [], summary: {},
      exceptions: [
        {
          user_type: 'Employee', user_id: '12345', issue_ids: [10, 11, 12],
          category: 'user_not_found', message: 'No Employee found with ID 12345'
        }
      ]
    )

    csv = rows(generate(result))

    assert_includes csv, ['Exceptions']
    assert_includes csv,
                    ['Employee', '12345', '10, 11, 12', 'user_not_found',
                     'No Employee found with ID 12345']
  end

  test 'changes section renders Applied as yes or no' do
    result = Result.new(
      exceptions: [], errors: [], summary: {},
      changes: [
        {
          issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          field: 'User Email', old_value: 'old@example.com', new_value: 'new@example.com',
          applied: true
        },
        {
          issue_id: 11, subject: 'Add AIX', user_type: 'Employee', user_id: '12345',
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

  test 'produces well-formed section headers even when empty' do
    csv = rows(generate(empty_result))

    # Both table header rows are always present.
    assert_includes csv, ['Exceptions']
    assert_includes csv, ['Changes']
    assert(csv.any? { |r| r.first == 'Account Holder Type' })
    assert(csv.any? { |r| r.first == 'Issue ID' })
  end
end
