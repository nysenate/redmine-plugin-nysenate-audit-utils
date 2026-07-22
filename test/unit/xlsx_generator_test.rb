# frozen_string_literal: true

require_relative '../test_helper'
require 'zip'

# Structural tests for the Excel exports. Each generator returns a serialized
# .xlsx (a zip of XML); we read it back with rubyzip and assert on the worksheet
# XML. caxlsx writes strings inline (no sharedStrings.xml), so cell text lives in
# the per-sheet XML.
class XlsxGeneratorTest < ActiveSupport::TestCase
  GEN = NysenateAuditUtils::Reporting::XlsxGenerator

  MONTHLY_ROW = {
    user_id: '12345', user_name: 'John Doe', user_type: 'Employee', user_uid: 'jdoe',
    status: 'active', account_action: 'Add', closed_on: Date.parse('2026-03-15'),
    request_code: 'OAA', issue_id: 100
  }.freeze

  DAILY_ROW = {
    user_name: 'John Doe', user_id: '12345', user_uid: 'jdoe', office: 'STS',
    office_location: 'Albany', status_changes: [{ code: 'TC1', notes: 'sample note' }],
    post_date: '2026-04-28', account_statuses: [{ request_code: 'OAA' }], open_requests: []
  }.freeze

  WEEKLY_ROW = {
    issue_id: 42, user_name: 'Jane Smith', user_uid: 'jsmith', user_id: '67890',
    office: 'Personnel', request_code: 'OAA', subject: 'Add account', status: 'New',
    created_on: Time.parse('2026-04-20 10:00'), closed_on: nil,
    updated_on: Time.parse('2026-04-22 14:30')
  }.freeze

  PERIODIC_ROW = {
    request_code: 'USRA', user_name: 'Alice Jones', user_uid: 'ajones', office: 'STS',
    created_on: Date.parse('2026-02-01'), closed_on: Date.parse('2026-02-10'),
    bac_number: 'BAC-1', issue_id: 200, subject: 'SFMS access'
  }.freeze

  ACCOUNT_HOLDER_ACCESS_ROW = {
    user_name: 'John Doe', user_id: '12345', user_uid: 'jdoe', user_type: 'Employee',
    user_office: 'Senate Office', account_type: 'Oracle / SFMS', request_code: 'USRA',
    status: 'active', issue_id: 100
  }.freeze

  # --- helpers -------------------------------------------------------------

  # Names of the worksheets in a workbook, in order.
  def sheet_names(xlsx)
    names = nil
    Zip::File.open_buffer(xlsx) do |z|
      names = z.read('xl/workbook.xml').scan(/<sheet[^>]*\bname="([^"]+)"/).flatten
    end
    names
  end

  # Concatenated XML of the Nth worksheet (1-based).
  def sheet_xml(xlsx, index = 1)
    xml = nil
    Zip::File.open_buffer(xlsx) { |z| xml = z.read("xl/worksheets/sheet#{index}.xml") }
    xml
  end

  # Count <row> elements in a worksheet.
  def row_count(xlsx, index = 1)
    sheet_xml(xlsx, index).scan(/<row[ >]/).size
  end

  def assert_valid_xlsx(xlsx)
    assert_kind_of String, xlsx
    assert_operator xlsx.bytesize, :>, 0
    assert_equal 'PK', xlsx[0, 2], 'expected a zip (xlsx) signature'
  end

  # Number of Excel table parts (xl/tables/tableN.xml) in the workbook. A
  # header-only table corrupts the file in Excel, so empty reports must have 0.
  def table_part_count(xlsx)
    count = 0
    Zip::File.open_buffer(xlsx) do |z|
      count = z.count { |e| e.name.start_with?('xl/tables/table') }
    end
    count
  end

  # --- daily ---------------------------------------------------------------

  def test_daily_xlsx_structure_and_content
    from = Time.parse('2026-04-28 00:00:00')
    to   = Time.parse('2026-04-29 00:00:00')
    xlsx = GEN.generate_daily_xlsx([DAILY_ROW], from_date: from, to_date: to)
    assert_valid_xlsx(xlsx)
    assert_equal ['Daily'], sheet_names(xlsx)

    xml = sheet_xml(xlsx)
    assert_includes xml, 'Report Name'
    # #18834: Daily carries a Report Purpose row in the heading.
    assert_includes xml, 'Report Purpose'
    assert_includes xml, 'Review for potential Offboarding and/or Onboarding security work.'
    assert_includes xml, 'Account Holder Name'
    assert_includes xml, 'John Doe'
    # 6 metadata (incl. Report Purpose) + blank + header + 1 data = 9 rows
    assert_equal 9, row_count(xlsx)
  end

  def test_daily_xlsx_omits_metadata_when_dates_missing
    xlsx = GEN.generate_daily_xlsx([DAILY_ROW])
    # header + 1 data row only
    assert_equal 2, row_count(xlsx)
    assert_not_includes sheet_xml(xlsx), 'Report Name'
  end

  def test_daily_xlsx_nil_data_returns_blank
    assert_equal '', GEN.generate_daily_xlsx(nil)
  end

  # #18834: empty data writes the on-screen "none found" message and emits NO
  # Excel table (a header-only table opens corrupt in Excel).
  def test_daily_xlsx_empty_writes_no_entries_message_and_no_table
    from = Time.parse('2026-04-28 00:00:00')
    to   = Time.parse('2026-04-29 00:00:00')
    xlsx = GEN.generate_daily_xlsx([], from_date: from, to_date: to)
    assert_valid_xlsx(xlsx)
    assert_equal 0, table_part_count(xlsx)
    assert_includes sheet_xml(xlsx), 'No user status changes found for the query period.'
    assert_not_includes sheet_xml(xlsx), 'Account Holder Name'
  end

  def test_weekly_xlsx_empty_writes_no_entries_message_and_no_table
    xlsx = GEN.generate_weekly_xlsx([], from_date: Date.parse('2026-04-27'), to_date: Time.parse('2026-05-01 00:00'))
    assert_equal 0, table_part_count(xlsx)
    assert_includes sheet_xml(xlsx), 'No closed tickets found for the selected period.'
  end

  def test_monthly_xlsx_empty_writes_no_entries_message_and_no_table
    xlsx = GEN.generate_monthly_xlsx([], as_of_time: Time.parse('2026-04-01 00:00'), target_system: 'AIX')
    assert_equal 0, table_part_count(xlsx)
    assert_includes sheet_xml(xlsx), 'No account data found for AIX as of April 2026.'
  end

  def test_periodic_xlsx_empty_writes_interpolated_no_entries_message
    xlsx = GEN.generate_periodic_xlsx([], system: 'sfms',
                                          from_date: Date.parse('2026-02-01'), to_date: Date.parse('2026-04-30'))
    assert_equal 0, table_part_count(xlsx)
    assert_includes sheet_xml(xlsx), 'No closed SFMS tickets found between 2026-02-01 and 2026-04-30.'
  end

  def test_account_holder_access_xlsx_empty_writes_no_entries_message
    xlsx = GEN.generate_account_holder_access_xlsx([])
    assert_equal 0, table_part_count(xlsx)
    assert_includes sheet_xml(xlsx), 'No account access found.'
  end

  # --- weekly --------------------------------------------------------------

  def test_weekly_xlsx_structure_and_content
    from = Date.parse('2026-04-27')
    to   = Time.parse('2026-05-01 23:59:59')
    xlsx = GEN.generate_weekly_xlsx([WEEKLY_ROW], from_date: from, to_date: to)
    assert_valid_xlsx(xlsx)
    assert_equal ['Weekly'], sheet_names(xlsx)
    xml = sheet_xml(xlsx)
    assert_includes xml, 'Ticket #'
    assert_includes xml, 'Jane Smith'
    assert_equal 8, row_count(xlsx)
  end

  def test_weekly_xlsx_nil_data_returns_blank
    assert_equal '', GEN.generate_weekly_xlsx(nil)
  end

  # --- periodic ------------------------------------------------------------

  def test_periodic_xlsx_has_no_metadata_and_matches_legacy_headers
    xlsx = GEN.generate_periodic_xlsx([PERIODIC_ROW])
    assert_valid_xlsx(xlsx)
    xml = sheet_xml(xlsx)
    assert_includes xml, 'RequestType'
    assert_includes xml, 'Alice Jones'
    assert_not_includes xml, 'Report Name'
    # header + 1 data row (no metadata preamble)
    assert_equal 2, row_count(xlsx)
  end

  def test_periodic_xlsx_nil_data_returns_blank
    assert_equal '', GEN.generate_periodic_xlsx(nil)
  end

  # --- monthly -------------------------------------------------------------

  def test_monthly_xlsx_structure_and_content
    as_of = Time.parse('2026-04-01 00:00:00')
    xlsx = GEN.generate_monthly_xlsx([MONTHLY_ROW], as_of_time: as_of, target_system: 'Oracle / SFMS')
    assert_valid_xlsx(xlsx)
    # sheet name sanitized: '/' -> space
    assert_equal ['Oracle   SFMS'], sheet_names(xlsx)
    xml = sheet_xml(xlsx)
    assert_includes xml, 'Account Holder Name'
    assert_includes xml, 'John Doe'
    assert_equal 8, row_count(xlsx)
  end

  def test_monthly_xlsx_nil_data_returns_blank
    assert_equal '', GEN.generate_monthly_xlsx(nil)
  end

  # --- all systems (single multi-sheet workbook) ---------------------------

  def test_all_systems_xlsx_one_sheet_per_system
    reports = {
      'Oracle / SFMS' => [MONTHLY_ROW],
      'AIX'           => [MONTHLY_ROW.merge(user_name: 'Jane Smith')]
    }
    xlsx = GEN.generate_all_systems_xlsx(reports, as_of_time: Time.parse('2026-04-01 00:00:00'))
    assert_valid_xlsx(xlsx)
    assert_equal ['Oracle   SFMS', 'AIX'], sheet_names(xlsx)
    assert_includes sheet_xml(xlsx, 1), 'John Doe'
    assert_includes sheet_xml(xlsx, 2), 'Jane Smith'
  end

  def test_all_systems_xlsx_empty_reports
    # No systems => a valid, empty workbook with no per-system worksheets
    # (caxlsx supplies a single default sheet).
    xlsx = GEN.generate_all_systems_xlsx({})
    assert_valid_xlsx(xlsx)
    assert_not_includes sheet_names(xlsx), 'Oracle   SFMS'
    assert_not_includes sheet_names(xlsx), 'AIX'
  end

  # --- account holder access ----------------------------------------------

  def test_account_holder_access_xlsx_structure_and_content
    xlsx = GEN.generate_account_holder_access_xlsx([
                                                     ACCOUNT_HOLDER_ACCESS_ROW,
                                                     ACCOUNT_HOLDER_ACCESS_ROW.merge(account_type: 'AIX', request_code: 'AIXD', status: 'inactive')
                                                   ])
    assert_valid_xlsx(xlsx)
    assert_equal ['Account Holder Access'], sheet_names(xlsx)
    xml = sheet_xml(xlsx)
    assert_includes xml, 'Target System'
    assert_includes xml, 'Active'
    assert_includes xml, 'Inactive'
    # 5 metadata + blank + header + 2 data = 9 rows
    assert_equal 9, row_count(xlsx)
  end

  def test_account_holder_access_xlsx_nil_data_returns_blank
    assert_equal '', GEN.generate_account_holder_access_xlsx(nil)
  end
end
