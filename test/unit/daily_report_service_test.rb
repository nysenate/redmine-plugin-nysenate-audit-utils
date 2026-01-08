# frozen_string_literal: true

require_relative '../test_helper'

class DailyReportServiceTest < ActiveSupport::TestCase
  def setup
    @service = NysenateAuditUtils::Reporting::DailyReportService.new
  end

  test 'initializes with default dates' do
    service = NysenateAuditUtils::Reporting::DailyReportService.new
    assert_not_nil service.from_date
    assert_not_nil service.to_date
    assert_equal [], service.status_changes
    assert_equal [], service.errors
  end

  test 'initializes with custom dates' do
    from = 2.days.ago
    to = 1.day.ago
    service = NysenateAuditUtils::Reporting::DailyReportService.new(from_date: from, to_date: to)

    assert_equal from, service.from_date
    assert_equal to, service.to_date
  end

  test 'default from_date uses query_start_date' do
    service = NysenateAuditUtils::Reporting::DailyReportService.new
    expected_date = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date

    assert_equal expected_date.to_date, service.from_date.to_date
  end

  test 'generate returns empty array when no status changes' do
    mock_ess_api([])

    result = @service.generate

    assert_equal [], result
    assert @service.success?
  end

  test 'generate handles ESS API errors gracefully' do
    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:changes_for_date_range).raises(StandardError, 'API Error')

    result = @service.generate

    assert_nil result
    assert_not @service.success?
    assert_match(/Failed to fetch status changes/, @service.errors.first)
  end

  test 'generate builds report data with single status change' do
    changes = [create_mock_status_change(employee_id: 12345)]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_equal 1, result.size
    assert_equal 'John Doe', result.first[:employee_name]
    assert_equal [], result.first[:account_statuses]
    assert_equal [], result.first[:open_requests]
    assert_equal 'APP', result.first[:transaction_codes]
    assert_equal 12345, result.first[:employee_id]
  end

  test 'generate builds report data with multiple status changes' do
    changes = [
      create_mock_status_change(employee_id: 12345, first_name: 'John', last_name: 'Doe'),
      create_mock_status_change(employee_id: 67890, first_name: 'Jane', last_name: 'Smith', transaction_code: 'EMP')
    ]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])
    mock_account_tracking('67890', [], [])

    result = @service.generate

    assert_equal 2, result.size
    assert_equal 'John Doe', result.first[:employee_name]
    assert_equal [], result.first[:account_statuses]
    assert_equal 'Jane Smith', result.last[:employee_name]
    assert_equal [], result.last[:open_requests]
  end

  test 'generate includes all required fields in report data' do
    changes = [create_mock_status_change]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate
    row = result.first

    assert row.key?(:employee_name)
    assert row.key?(:account_statuses)
    assert row.key?(:open_requests)
    assert row.key?(:transaction_codes)
    assert row.key?(:phone_number)
    assert row.key?(:office)
    assert row.key?(:office_location)
    assert row.key?(:employee_id)
    assert row.key?(:post_date)
  end

  test 'generate includes transaction codes' do
    changes = [create_mock_status_change(transaction_code: 'APP')]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_equal 'APP', result.first[:transaction_codes]
  end

  test 'generate includes employee contact and office info' do
    changes = [create_mock_status_change]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_equal '555-1234', result.first[:phone_number]
    assert_equal 'Test Office', result.first[:office]
  end

  test 'generate sets office_location' do
    changes = [create_mock_status_change]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_equal "TEST", result.first[:office_location]
  end

  test 'generate includes account statuses' do
    changes = [create_mock_status_change(employee_id: 12345)]
    mock_ess_api(changes)
    statuses = [
      { account_type: 'Oracle / SFMS', status: 'active', request_code: 'USRA', issue_id: 1 }
    ]
    mock_account_tracking('12345', statuses, [])

    result = @service.generate

    assert_equal 1, result.first[:account_statuses].size
    assert_equal 'USRA', result.first[:account_statuses].first[:request_code]
  end

  test 'generate includes open requests' do
    changes = [create_mock_status_change(employee_id: 12345)]
    mock_ess_api(changes)
    open_requests = [
      { account_type: 'AIX', request_code: 'AIXA', issue_id: 2 }
    ]
    mock_account_tracking('12345', [], open_requests)

    result = @service.generate

    assert_equal 1, result.first[:open_requests].size
    assert_equal 'AIXA', result.first[:open_requests].first[:request_code]
  end

  test 'generate converts post_date_time to date' do
    post_datetime = DateTime.new(2025, 1, 15, 10, 30, 0)
    changes = [create_mock_status_change(post_date_time: post_datetime)]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_equal Date.new(2025, 1, 15), result.first[:post_date]
  end

  test 'generate handles nil post_date_time' do
    changes = [create_mock_status_change(post_date_time: nil)]
    mock_ess_api(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    assert_nil result.first[:post_date]
  end

  test 'generate groups multiple transactions for same employee' do
    # Two changes for same employee
    changes = [
      create_mock_status_change(employee_id: 12345, transaction_code: 'APP'),
      create_mock_status_change(employee_id: 12345, transaction_code: 'PHO')
    ]

    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:changes_for_date_range).returns(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    # Should return only one row for the employee with combined transaction codes
    assert_equal 1, result.size
    assert_equal 12345, result.first[:employee_id]
    assert_equal 'APP, PHO', result.first[:transaction_codes]
  end

  test 'generate uses latest post date for grouped transactions' do
    # Two changes for same employee with different post dates
    early_date = DateTime.new(2025, 1, 10, 10, 0, 0)
    late_date = DateTime.new(2025, 1, 15, 10, 0, 0)

    changes = [
      create_mock_status_change(employee_id: 12345, transaction_code: 'APP', post_date_time: early_date),
      create_mock_status_change(employee_id: 12345, transaction_code: 'PHO', post_date_time: late_date)
    ]

    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:changes_for_date_range).returns(changes)
    mock_account_tracking('12345', [], [])

    result = @service.generate

    # Should use the latest post date
    assert_equal 1, result.size
    assert_equal Date.new(2025, 1, 15), result.first[:post_date]
  end

  test 'success? returns true when no errors' do
    mock_ess_api([])
    @service.generate

    assert @service.success?
  end

  test 'success? returns false when errors present' do
    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:changes_for_date_range).raises('Error')

    @service.generate

    assert_not @service.success?
  end

  private

  def create_mock_status_change(
    employee_id: 12345,
    first_name: 'John',
    last_name: 'Doe',
    transaction_code: 'APP',
    post_date_time: DateTime.now,
    work_phone: '555-1234',
    office_short_name: 'Test Office'
  )
    employee_data = {
      employee_id: employee_id,
      first_name: first_name,
      last_name: last_name,
      full_name: "#{first_name} #{last_name}",
      work_phone: work_phone,
      location: EssLocation.new(
        loc_id: 'TEST-W',
        code: 'TEST',
        resp_center_head: EssResponsibilityCenterHead.new(
          code: 'TEST',
          short_name: office_short_name,
          name: 'Test Office Full Name'
        )
      )
    }

    EssStatusChange.new(
      transaction_code: transaction_code,
      post_date_time: post_date_time,
      employee_data: employee_data
    )
  end

  def mock_ess_api(changes)
    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:changes_for_date_range).returns(changes)
  end

  def mock_account_tracking(employee_id, account_statuses, open_requests)
    # Initialize expectations hash if not exists
    @account_tracking_expectations ||= {}
    @account_tracking_expectations[employee_id.to_s] = {
      statuses: account_statuses,
      requests: open_requests
    }

    # Create mock service that can access the instance variable
    test_instance = self
    service = Object.new

    service.define_singleton_method(:get_account_statuses) do |emp_id|
      test_instance.instance_variable_get(:@account_tracking_expectations)[emp_id.to_s]&.dig(:statuses) || []
    end

    service.define_singleton_method(:get_open_account_requests) do |emp_id|
      test_instance.instance_variable_get(:@account_tracking_expectations)[emp_id.to_s]&.dig(:requests) || []
    end

    # Stub the class to return our mock service
    NysenateAuditUtils::AccountTracking::AccountTrackingService.stubs(:new).returns(service)
  end
end
