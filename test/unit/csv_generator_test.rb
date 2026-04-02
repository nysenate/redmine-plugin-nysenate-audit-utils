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
      assert_match /User Name/, csv_content
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
end
