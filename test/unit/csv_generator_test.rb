# frozen_string_literal: true

require_relative '../test_helper'
require 'zip'

class CsvGeneratorTest < ActiveSupport::TestCase
  MONTHLY_ROW = {
    user_id: '12345',
    user_name: 'John Doe',
    user_type: 'Employee',
    user_uid: 'jdoe',
    status: 'active',
    account_action: 'Add',
    closed_on: Date.parse('2026-03-15'),
    request_code: 'OAA',
    issue_id: 100
  }.freeze

  def test_generate_all_systems_zip_returns_binary_string
    reports = { 'Oracle / SFMS' => [MONTHLY_ROW] }
    result = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, 'current')
    assert_kind_of String, result
    assert result.length > 0
  end

  def test_generate_all_systems_zip_contains_one_csv_per_system
    reports = {
      'Oracle / SFMS' => [MONTHLY_ROW],
      'AIX'           => [MONTHLY_ROW.merge(user_id: '99999', user_name: 'Jane Smith')]
    }
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, 'current')

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      entries = []
      while (entry = zip.get_next_entry)
        entries << entry.name
      end
      assert_includes entries, 'monthly_report_oracle-sfms_current.csv'
      assert_includes entries, 'monthly_report_aix_current.csv'
      assert_equal 2, entries.size
    end
  end

  def test_generate_all_systems_zip_csv_content_is_correct
    reports = { 'SFS' => [MONTHLY_ROW.merge(user_name: 'Alice', user_id: '55555')] }
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, '202603')

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      entry = zip.get_next_entry
      assert_equal 'monthly_report_sfs_202603.csv', entry.name
      csv_content = zip.read
      assert_match /Account Holder Name/, csv_content
      assert_match /Alice/, csv_content
      assert_match /55555/, csv_content
    end
  end

  def test_generate_all_systems_zip_uses_parameterized_system_name
    reports = { 'Oracle / SFMS' => [] }
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, '202601')

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      entry = zip.get_next_entry
      assert_equal 'monthly_report_oracle-sfms_202601.csv', entry.name
    end
  end

  def test_generate_all_systems_zip_with_empty_reports
    reports = {}
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, 'current')
    assert_kind_of String, zip_data

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      assert_nil zip.get_next_entry
    end
  end

  def test_generate_all_systems_zip_monthly_suffix
    reports = { 'AIX' => [MONTHLY_ROW] }
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports, '202604')

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      entry = zip.get_next_entry
      assert_equal 'monthly_report_aix_202604.csv', entry.name
    end
  end

  # --- Metadata header tests ---

  DAILY_ROW = {
    user_name: 'John Doe',
    user_id: '12345',
    user_uid: 'jdoe',
    office: 'STS',
    office_location: 'Albany',
    transaction_codes: 'TC1',
    post_date: '2026-04-28',
    account_statuses: [{ request_code: 'OAA' }],
    open_requests: []
  }.freeze

  WEEKLY_ROW = {
    issue_id: 42,
    user_name: 'Jane Smith',
    user_uid: 'jsmith',
    user_id: '67890',
    office: 'Personnel',
    request_code: 'OAA',
    subject: 'Add account',
    status: 'New',
    created_on: Time.parse('2026-04-20 10:00'),
    closed_on: nil,
    updated_on: Time.parse('2026-04-22 14:30')
  }.freeze

  def test_daily_csv_includes_metadata_block_when_dates_provided
    from = Time.parse('2026-04-28 00:00:00')
    to   = Time.parse('2026-04-29 00:00:00')
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(
      [DAILY_ROW], from_date: from, to_date: to
    )
    lines = csv.lines
    assert_equal 'Report Name,Daily', lines[0].chomp
    assert_match(/^Report Description,/, lines[1])
    assert_match(/^Start time,2026-04-28 00:00:00/, lines[2])
    assert_match(/^End time,2026-04-29 00:00:00/, lines[3])
    assert_match(/^Generated at,\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, lines[4])
    assert_equal '', lines[5].chomp
    assert_match(/Account Holder Name/, lines[6])
    assert_match(/John Doe/, lines[7])
  end

  def test_daily_csv_omits_metadata_when_dates_missing
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv([DAILY_ROW])
    assert_match(/\AAccount Holder Name/, csv)
  end

  def test_weekly_csv_includes_metadata_block_when_dates_provided
    from = Date.parse('2026-04-27')
    to   = Time.parse('2026-05-01 23:59:59')
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv(
      [WEEKLY_ROW], from_date: from, to_date: to
    )
    lines = csv.lines
    assert_equal 'Report Name,Weekly', lines[0].chomp
    assert_match(/^Report Description,/, lines[1])
    assert_match(/^Start time,2026-04-27/, lines[2])
    assert_match(/^End time,2026-05-01 23:59:59/, lines[3])
    assert_match(/^Generated at,\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, lines[4])
    assert_equal '', lines[5].chomp
    assert_match(/Ticket #/, lines[6])
  end

  def test_weekly_csv_omits_metadata_when_dates_missing
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv([WEEKLY_ROW])
    assert_match(/\ATicket #/, csv)
  end

  def test_monthly_csv_includes_metadata_block_with_target_system
    as_of = Time.parse('2026-04-01 00:00:00')
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_monthly_csv(
      [MONTHLY_ROW], as_of_time: as_of, target_system: 'Oracle / SFMS'
    )
    lines = csv.lines
    assert_equal 'Report Name,Monthly', lines[0].chomp
    assert_match(/Oracle \/ SFMS/, lines[1])
    assert_equal 'Start time,N/A', lines[2].chomp
    assert_match(/^End time,2026-04-01 00:00:00/, lines[3])
    assert_match(/^Generated at,\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, lines[4])
    assert_equal '', lines[5].chomp
    assert_match(/Account Holder Name/, lines[6])
  end

  def test_monthly_csv_omits_metadata_when_as_of_time_missing
    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_monthly_csv([MONTHLY_ROW])
    assert_match(/\AAccount Holder Name/, csv)
  end

  def test_all_systems_zip_includes_metadata_per_csv
    as_of = Time.parse('2026-04-01 00:00:00')
    reports = {
      'Oracle / SFMS' => [MONTHLY_ROW],
      'AIX'           => [MONTHLY_ROW]
    }
    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(
      reports, '202604', as_of_time: as_of
    )

    Zip::InputStream.open(StringIO.new(zip_data)) do |zip|
      while (entry = zip.get_next_entry)
        content = zip.read
        assert_match(/^Report Name,Monthly/, content)
        if entry.name.include?('oracle-sfms')
          assert_match(/Oracle \/ SFMS/, content)
        elsif entry.name.include?('aix')
          assert_match(/AIX/, content)
        end
        assert_match(/^Start time,N\/A/, content)
        assert_match(/^End time,2026-04-01/, content)
      end
    end
  end
end
