# frozen_string_literal: true

require_relative '../test_helper'
require 'zip'

class UserInfoAuditXlsxGeneratorTest < ActiveSupport::TestCase
  Result = NysenateAuditUtils::Reporting::UserInfoAuditService::Result

  def setup
    @project = Struct.new(:identifier).new('testproj')
    @generated_at = Time.new(2026, 6, 9, 14, 30, 0, '+00:00')
  end

  def generate(result, dry_run: false)
    NysenateAuditUtils::Reporting::UserInfoAuditXlsxGenerator.generate(
      result, project: @project, dry_run: dry_run, generated_at: @generated_at
    )
  end

  def empty_result
    Result.new(changes: [], unmatched: [], summary: {}, errors: [])
  end

  # Concatenated worksheet XML (single sheet; caxlsx writes strings inline).
  def sheet_text(xlsx)
    xml = nil
    Zip::File.open_buffer(xlsx) { |z| xml = z.read('xl/worksheets/sheet1.xml') }
    xml
  end

  def sheet_names(xlsx)
    names = nil
    Zip::File.open_buffer(xlsx) do |z|
      names = z.read('xl/workbook.xml').scan(/<sheet[^>]*\bname="([^"]+)"/).flatten
    end
    names
  end

  test 'produces a valid single-sheet workbook' do
    xlsx = generate(empty_result)
    assert_equal 'PK', xlsx[0, 2]
    assert_equal ['Account Holder Info Audit'], sheet_names(xlsx)
  end

  test 'header includes report name, project and mode' do
    xml = sheet_text(generate(empty_result, dry_run: true))
    assert_includes xml, 'Account Holder Info Audit'
    assert_includes xml, 'testproj'
    assert_includes xml, 'Dry run (no changes applied)'
  end

  test 'header uses apply mode when not a dry run' do
    assert_includes sheet_text(generate(empty_result, dry_run: false)), 'Apply'
  end

  test 'both section titles are always present' do
    xml = sheet_text(generate(empty_result))
    assert_includes xml, 'Unmatched Tickets'
    assert_includes xml, 'Changes'
  end

  test 'unmatched section lists affected tickets' do
    result = Result.new(
      changes: [], errors: [], summary: {},
      unmatched: [
        { issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe', category: 'user_not_found',
          message: 'No Employee found with ID 12345' }
      ]
    )
    xml = sheet_text(generate(result))
    assert_includes xml, 'Add Oracle'
    assert_includes xml, 'user_not_found'
    assert_includes xml, 'Jane Doe'
  end

  test 'changes section renders applied as yes or no' do
    result = Result.new(
      unmatched: [], errors: [], summary: {},
      changes: [
        { issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe', field: 'Account Holder Email',
          old_value: 'old@example.com', new_value: 'new@example.com', applied: true },
        { issue_id: 11, subject: 'Add AIX', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe', field: 'Account Holder Phone',
          old_value: '555-0000', new_value: '555-1111', applied: false }
      ]
    )
    xml = sheet_text(generate(result))
    assert_includes xml, 'new@example.com'
    assert_includes xml, '555-1111'
    assert_includes xml, '>yes<'
    assert_includes xml, '>no<'
  end

  test 'row count reflects header, sections, and data rows' do
    result = Result.new(
      changes: [
        { issue_id: 10, subject: 'Add Oracle', user_type: 'Employee', user_id: '12345',
          account_holder_name: 'Jane Doe', field: 'Account Holder Email',
          old_value: 'a', new_value: 'b', applied: true }
      ],
      unmatched: [
        { issue_id: 20, subject: 'Add SFS', user_type: 'Employee', user_id: '999',
          account_holder_name: nil, category: 'user_not_found', message: 'missing' }
      ],
      summary: { tickets_scanned: 5 }, errors: []
    )
    xlsx = generate(result)
    row_count = sheet_text(xlsx).scan(/<row[ >]/).size
    # header kv rows (Report Name..Tickets to update = 6, no by-category) + blank
    # + Unmatched title + unmatched header + 1 unmatched + blank
    # + Changes title + changes header + 1 change
    assert_operator row_count, :>=, 12
  end
end
