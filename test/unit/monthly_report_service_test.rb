# frozen_string_literal: true

require_relative '../test_helper'

class MonthlyReportServiceTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers,
           :enumerations, :custom_fields, :custom_values

  def setup
    @project = Project.find(1)
    @tracker = Tracker.find(1)

    # Use helper to setup standard fields and associate with tracker
    @fields = setup_standard_bachelp_fields(@tracker)
    @employee_id_field = @fields[:user_id]
    @employee_name_field = @fields[:user_name]
    @account_action_field = @fields[:account_action]
    @target_system_field = @fields[:target_system]

    # Get closed and open status
    @closed_status = IssueStatus.where(is_closed: true).first
  end

  def teardown
    clear_audit_configuration
  end

  test 'initializes with target system' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    assert_equal 'Oracle / SFMS', service.target_system
    assert_equal [], service.errors
  end

  test 'generate returns report data for valid system' do
    # Create test issue with closed status
    issue = create_closed_test_issue('12345', 'John Doe', 'Oracle / SFMS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    result = service.generate

    assert_not_nil result
    assert_equal 1, result.size
    assert service.success?

    row = result.first
    assert_equal '12345', row[:user_id]
    assert_equal 'John Doe', row[:user_name]
    assert_equal 'Oracle / SFMS', row[:account_type]
    assert_equal 'active', row[:status]
    assert_equal 'Add', row[:account_action]
    assert_not_nil row[:closed_on]
    assert_not_nil row[:request_code]
    assert_equal issue.id, row[:issue_id]
  end

  test 'generate returns empty array for system with no data' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'AIX')
    result = service.generate

    assert_equal [], result
    assert service.success?
  end

  test 'generate includes employee names from custom field' do
    # Create issues with Employee Name custom field populated
    issue1 = create_closed_test_issue('12345', 'Alice Smith', 'SFS', 'Add', 1.day.ago)
    issue2 = create_closed_test_issue('67890', 'Bob Jones', 'SFS', 'Delete', 2.days.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'SFS')
    result = service.generate

    assert_equal 2, result.size
    assert_equal 'Alice Smith', result.find { |r| r[:user_id] == '12345' }[:user_name]
    assert_equal 'Bob Jones', result.find { |r| r[:user_id] == '67890' }[:user_name]
  end

  test 'generate handles missing employee name gracefully' do
    # Create issue without Employee Name field
    issue = create_closed_test_issue('12345', nil, 'AIX', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'AIX')
    result = service.generate

    assert_equal 1, result.size
    assert_nil result.first[:user_name]
  end

  test 'generate sorts by employee_id' do
    # Create multiple employees in random order
    issue3 = create_closed_test_issue('99999', 'Zach Last', 'NYSDS', 'Add', 1.day.ago)
    issue1 = create_closed_test_issue('11111', 'Alice First', 'NYSDS', 'Add', 1.day.ago)
    issue2 = create_closed_test_issue('55555', 'Mike Middle', 'NYSDS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'NYSDS')
    result = service.generate

    assert_equal 3, result.size
    assert_equal '11111', result[0][:user_id]
    assert_equal '55555', result[1][:user_id]
    assert_equal '99999', result[2][:user_id]
  end

  test 'generate handles errors gracefully' do
    # Mock AccountTrackingService instance to raise error
    mock_service = mock('account_tracking_service')
    mock_service.stubs(:get_account_statuses_by_system).raises(StandardError, 'Database error')
    NysenateAuditUtils::AccountTracking::AccountTrackingService.stubs(:new).returns(mock_service)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    result = service.generate

    assert_nil result
    assert_not service.success?
    assert_match(/Failed to fetch account statuses|Report generation failed/, service.errors.first)
  end

  test 'generate includes all required fields' do
    issue = create_closed_test_issue('12345', 'John Doe', 'PayServ', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'PayServ')
    result = service.generate

    row = result.first
    assert row.key?(:user_id)
    assert row.key?(:user_name)
    assert row.key?(:user_type)
    assert row.key?(:account_type)
    assert row.key?(:status)
    assert row.key?(:account_action)
    assert row.key?(:closed_on)
    assert row.key?(:request_code)
    assert row.key?(:issue_id)
  end

  test 'generate filters by target system correctly' do
    # Create issues for different systems
    oracle_issue = create_closed_test_issue('11111', 'User One', 'Oracle / SFMS', 'Add', 1.day.ago)
    aix_issue = create_closed_test_issue('22222', 'User Two', 'AIX', 'Add', 1.day.ago)

    # Query for Oracle only
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    result = service.generate

    assert_equal 1, result.size
    assert_equal '11111', result.first[:user_id]
    assert_equal 'Oracle / SFMS', result.first[:account_type]
  end

  test 'generate returns most recent issue when employee has multiple closed issues' do
    # Create multiple closed issues for same employee and system
    old_issue = create_closed_test_issue('12345', 'John Doe', 'OGS Swiper Access', 'Add', 10.days.ago)
    recent_issue = create_closed_test_issue('12345', 'John Doe', 'OGS Swiper Access', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'OGS Swiper Access')
    result = service.generate

    # Should return only one row with the most recent issue
    assert_equal 1, result.size
    assert_equal recent_issue.id, result.first[:issue_id]
    assert_equal 'Delete', result.first[:account_action]
    assert_equal 'inactive', result.first[:status]
  end

  test 'success? returns true when no errors' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'AIX')
    service.generate

    assert service.success?
  end

  test 'success? returns false when errors present' do
    mock_service = mock('account_tracking_service')
    mock_service.stubs(:get_account_statuses_by_system).raises('Error')
    NysenateAuditUtils::AccountTracking::AccountTrackingService.stubs(:new).returns(mock_service)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    service.generate

    assert_not service.success?
  end

  test 'validate handles blank target system' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: '')
    result = service.generate

    # Blank target system should be allowed (returns empty results)
    assert_equal [], result
    assert service.success?
  end

  test 'validate rejects invalid target system' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Invalid System')
    result = service.generate

    assert_nil result
    assert_not service.success?
    assert_match(/Invalid target system/, service.errors.first)
  end

  test 'generate excludes issues with blank user_id' do
    # Create a closed issue without User ID field
    issue_without_user_id = Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Issue without User ID",
      status: @closed_status,
      priority_id: 5,
      custom_field_values: {
        @target_system_field.id => 'Oracle / SFMS',
        @account_action_field.id => 'Add',
        @employee_name_field.id => 'Test User'
      }
    )
    Issue.where(id: issue_without_user_id.id).update_all(closed_on: 1.day.ago)

    # Create a normal issue with User ID for comparison
    issue_with_user_id = create_closed_test_issue('12345', 'Valid User', 'Oracle / SFMS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    result = service.generate

    # Should only include the issue with User ID
    assert_equal 1, result.size
    assert_equal '12345', result.first[:user_id]
    assert_equal issue_with_user_id.id, result.first[:issue_id]
  end

  # Tests for as_of_time parameter

  test 'initializes with as_of_time parameter' do
    cutoff_time = 3.days.ago
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'Oracle / SFMS',
      as_of_time: cutoff_time
    )

    assert_equal 'Oracle / SFMS', service.target_system
    assert_equal cutoff_time, service.as_of_time
  end

  test 'defaults as_of_time to current time when not provided' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    # Should default to Time.current (within a few seconds)
    assert_not_nil service.as_of_time
    assert_instance_of ActiveSupport::TimeWithZone, service.as_of_time
    # Verify it's close to current time (within 5 seconds)
    assert_in_delta Time.current.to_i, service.as_of_time.to_i, 5
  end

  test 'generate respects as_of_time parameter' do
    cutoff_time = 3.days.ago

    # Create issues before and after cutoff
    old_issue = create_closed_test_issue('12345', 'Alice Before', 'AIX', 'Add', 5.days.ago)
    recent_issue = create_closed_test_issue('67890', 'Bob After', 'AIX', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'AIX',
      as_of_time: cutoff_time
    )
    result = service.generate

    # Should only include the old issue (before cutoff)
    assert_equal 1, result.size
    assert_equal '12345', result.first[:user_id]
    assert_equal 'Alice Before', result.first[:user_name]
    assert_equal old_issue.id, result.first[:issue_id]
  end

  test 'generate includes all closed issues when as_of_time not provided' do
    # Create issues at different times
    old_issue = create_closed_test_issue('12345', 'Alice Old', 'SFS', 'Add', 10.days.ago)
    recent_issue = create_closed_test_issue('67890', 'Bob Recent', 'SFS', 'Delete', 1.hour.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'SFS')
    result = service.generate

    # Should include both issues since as_of_time defaults to current
    assert_equal 2, result.size
    assert_includes result.map { |r| r[:user_id] }, '12345'
    assert_includes result.map { |r| r[:user_id] }, '67890'
  end

  test 'generate selects most recent Add/Delete issue before cutoff time' do
    cutoff_time = 2.days.ago

    # Create multiple issues for same employee, before and after cutoff
    # Only Add/Delete issues count; Update actions are ignored
    oldest = create_closed_test_issue('12345', 'Alice', 'NYSDS', 'Add', 10.days.ago)
    before_cutoff = create_closed_test_issue('12345', 'Alice', 'NYSDS', 'Delete', 3.days.ago)
    after_cutoff = create_closed_test_issue('12345', 'Alice', 'NYSDS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'NYSDS',
      as_of_time: cutoff_time
    )
    result = service.generate

    # Should return the most recent Add/Delete issue BEFORE cutoff (before_cutoff)
    assert_equal 1, result.size
    assert_equal '12345', result.first[:user_id]
    assert_equal before_cutoff.id, result.first[:issue_id]
    assert_equal 'Delete', result.first[:account_action]
    assert_equal 'inactive', result.first[:status]
  end

  # Tests for status_filter parameter

  test 'initializes with status_filter parameter' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'Oracle / SFMS',
      status_filter: 'active'
    )

    assert_equal 'Oracle / SFMS', service.target_system
    assert_equal 'active', service.status_filter
  end

  test 'defaults status_filter to all when not provided' do
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    assert_equal 'all', service.status_filter
  end

  test 'generate filters by active status only' do
    # Create active and inactive accounts for same system
    # Only Add/Delete issues count; Update actions are ignored
    active_issue1 = create_closed_test_issue('11111', 'Active User 1', 'AIX', 'Add', 3.days.ago)
    active_issue2 = create_closed_test_issue('22222', 'Active User 2', 'AIX', 'Add', 2.days.ago)
    inactive_issue = create_closed_test_issue('33333', 'Inactive User', 'AIX', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'AIX',
      status_filter: 'active'
    )
    result = service.generate

    # Should only return active accounts
    assert_equal 2, result.size
    assert_includes result.map { |r| r[:user_id] }, '11111'
    assert_includes result.map { |r| r[:user_id] }, '22222'
    assert_not_includes result.map { |r| r[:user_id] }, '33333'
    result.each { |r| assert_equal 'active', r[:status] }
  end

  test 'generate filters by inactive status only' do
    # Create active and inactive accounts for same system
    active_issue = create_closed_test_issue('11111', 'Active User', 'SFS', 'Add', 3.days.ago)
    inactive_issue1 = create_closed_test_issue('22222', 'Inactive User 1', 'SFS', 'Delete', 2.days.ago)
    inactive_issue2 = create_closed_test_issue('33333', 'Inactive User 2', 'SFS', 'Delete', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'SFS',
      status_filter: 'inactive'
    )
    result = service.generate

    # Should only return inactive accounts
    assert_equal 2, result.size
    assert_includes result.map { |r| r[:user_id] }, '22222'
    assert_includes result.map { |r| r[:user_id] }, '33333'
    assert_not_includes result.map { |r| r[:user_id] }, '11111'
    result.each { |r| assert_equal 'inactive', r[:status] }
  end

  test 'generate with all status filter returns all accounts' do
    # Create mix of active and inactive accounts
    active_issue = create_closed_test_issue('11111', 'Active User', 'NYSDS', 'Add', 3.days.ago)
    inactive_issue = create_closed_test_issue('22222', 'Inactive User', 'NYSDS', 'Delete', 2.days.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'NYSDS',
      status_filter: 'all'
    )
    result = service.generate

    # Should return both active and inactive accounts
    assert_equal 2, result.size
    assert_includes result.map { |r| r[:user_id] }, '11111'
    assert_includes result.map { |r| r[:user_id] }, '22222'
    assert_equal 'active', result.find { |r| r[:user_id] == '11111' }[:status]
    assert_equal 'inactive', result.find { |r| r[:user_id] == '22222' }[:status]
  end

  test 'generate with blank status filter returns all accounts' do
    # Create mix of active and inactive accounts
    active_issue = create_closed_test_issue('11111', 'Active User', 'PayServ', 'Add', 3.days.ago)
    inactive_issue = create_closed_test_issue('22222', 'Inactive User', 'PayServ', 'Delete', 2.days.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'PayServ',
      status_filter: ''
    )
    result = service.generate

    # Should return all accounts when filter is blank
    assert_equal 2, result.size
  end

  test 'generate returns empty array when no accounts match status filter' do
    # Create only active accounts
    active_issue = create_closed_test_issue('11111', 'Active User', 'Oracle / SFMS', 'Add', 1.day.ago)

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'Oracle / SFMS',
      status_filter: 'inactive'
    )
    result = service.generate

    # Should return empty array when no inactive accounts exist
    assert_equal [], result
  end

  test 'status filter works with as_of_time parameter' do
    # Create issues with different timestamps
    old_active = create_closed_test_issue('11111', 'Old Active', 'OGS Swiper Access', 'Add', 10.days.ago)
    old_inactive = create_closed_test_issue('22222', 'Old Inactive', 'OGS Swiper Access', 'Delete', 9.days.ago)
    recent_active = create_closed_test_issue('33333', 'Recent Active', 'OGS Swiper Access', 'Add', 1.day.ago)

    cutoff_time = 5.days.ago

    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: 'OGS Swiper Access',
      as_of_time: cutoff_time,
      status_filter: 'active'
    )
    result = service.generate

    # Should return only active accounts before cutoff
    assert_equal 1, result.size
    assert_equal '11111', result.first[:user_id]
    assert_equal 'active', result.first[:status]
  end

  private

  def create_test_issue(employee_id, employee_name, target_system, account_action)
    employee_id_field = CustomField.find_by(name: 'Employee ID')
    employee_name_field = CustomField.find_by(name: 'Employee Name')
    target_system_field = CustomField.find_by(name: 'Target System')
    account_action_field = CustomField.find_by(name: 'Account Action')

    issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      author: User.find(1),
      subject: "Test Issue for #{employee_id}",
      status: IssueStatus.find_by(name: 'New'),
      custom_field_values: {
        employee_id_field.id => employee_id,
        employee_name_field.id => employee_name,
        target_system_field.id => target_system,
        account_action_field.id => account_action
      }
    )
    issue.reload
  end

  def create_closed_test_issue(employee_id, employee_name, target_system, account_action, closed_time)
    custom_values = {
      @employee_id_field.id => employee_id.to_s,
      @target_system_field.id => target_system,
      @account_action_field.id => account_action
    }

    # Only add employee_name if provided
    custom_values[@employee_name_field.id] = employee_name if employee_name

    issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Test Issue for #{employee_id}",
      status: @closed_status,
      priority_id: 5,
      custom_field_values: custom_values
    )

    # Set closed_on using update_all to bypass callbacks
    Issue.where(id: issue.id).update_all(closed_on: closed_time)
    issue.reload
  end
end
