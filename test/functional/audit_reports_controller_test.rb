require File.expand_path('../../test_helper', __FILE__)

class AuditReportsControllerTest < ActionController::TestCase
  fixtures :users, :roles, :issues, :projects, :trackers, :issue_statuses, :enumerations, :members, :member_roles, :enabled_modules

  def setup
    @request.session[:user_id] = 1 # Admin user
    @project = Project.find(1)
    @project.enable_module!(:audit_utils_reporting)

    # Set up role permissions for the admin user
    role = Role.find(1)
    role.add_permission!(:view_audit_reports) unless role.permissions.include?(:view_audit_reports)
  end

  test "should get index" do
    get :index, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Audit Reports'
    assert_select 'a', text: 'Daily Report'
    assert_select 'a', text: 'Weekly Report'
    assert_select 'a', text: 'Monthly Report'
  end

  test "should require admin access for index" do
    @request.session[:user_id] = 2 # Non-admin user
    # Remove the permission from the Manager role
    role = Role.find(1)
    role.remove_permission!(:view_audit_reports) if role.permissions.include?(:view_audit_reports)
    get :index, params: { project_id: 1 }
    assert_response :forbidden
  end

  test "should get daily report" do
    # Mock the service to return test data
    mock_report_data = [
      {
        employee_name: 'John Doe',
        ticket_count: 2,
        ticket_url: '/issues?cf_1=12345',
        transaction_codes: 'APP',
        phone_number: '555-1234',
        office: 'IT',
        office_location: nil,
        employee_id: '12345',
        post_date: '2025-01-15'
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Daily Report'
    assert_select 'table.list.issues'
    # Verify employee name appears in table
    assert_select 'td', text: 'John Doe'
  end

  test "should require admin access for daily report" do
    @request.session[:user_id] = 2 # Non-admin user
    # Remove the permission from the Manager role
    role = Role.find(1)
    role.remove_permission!(:view_audit_reports) if role.permissions.include?(:view_audit_reports)
    get :daily, params: { project_id: 1 }
    assert_response :forbidden
  end

  test "should handle empty daily report data" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns([])
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }
    assert_response :success
    assert_select 'p.nodata', text: /No employee status changes found/
  end

  test "should handle nil daily report data" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns(nil)
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }
    assert_response :success
    assert_select 'p.nodata', text: /No employee status changes found/
  end

  test "should render error page on service failure" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns(nil)
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(false)
    service_mock.stubs(:errors).returns(['ESS API connection failed'])
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }
    assert_response :success
    # Verify error page content
    assert_select 'h2', text: 'Report Generation Error'
    assert_select 'div.flash.error'
  end

  test "should export daily report as CSV" do
    mock_report_data = [
      {
        employee_name: 'John Doe',
        ticket_count: 2,
        ticket_url: '/issues?cf_1=12345',
        transaction_codes: 'APP',
        phone_number: '555-1234',
        office: 'IT',
        office_location: nil,
        employee_id: '12345',
        post_date: '2025-01-15'
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }, format: :csv
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_match /attachment/, response.headers['Content-Disposition']
    assert_match /daily_report_.*\.csv/, response.headers['Content-Disposition']

    csv_content = response.body
    assert_match /Employee Name/, csv_content
    assert_match /John Doe/, csv_content
    assert_match /12345/, csv_content
  end

  test "should export empty CSV for nil report data" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns(nil)
    service_mock.stubs(:from_date).returns(Date.today - 1.day)
    service_mock.stubs(:to_date).returns(Date.today)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::DailyReportService.expects(:new).returns(service_mock)

    get :daily, params: { project_id: 1 }, format: :csv
    assert_response :success
    assert_equal '', response.body
  end

  test "should get monthly report with default system" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        account_type: 'Oracle / SFMS',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |args|
      args[:target_system] == 'Oracle / SFMS' &&
        args[:as_of_time].present?
    end.returns(service_mock)

    get :monthly, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Monthly Report'
    assert_select 'table.list.issues'
    assert_select 'td', text: 'John Doe'
    assert_select 'select#target_system option[selected]', text: 'Oracle / SFMS'
  end

  test "should get monthly report with specified system" do
    mock_report_data = [
      {
        employee_id: '54321',
        employee_name: 'Jane Smith',
        account_type: 'AIX',
        status: 'inactive',
        account_action: 'Delete',
        closed_on: Date.today - 2.days,
        request_code: 'RC2',
        issue_id: 2
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |args|
      args[:target_system] == 'AIX' &&
        args[:as_of_time].present?
    end.returns(service_mock)

    get :monthly, params: { project_id: 1, target_system: 'AIX' }
    assert_response :success
    assert_select 'select#target_system option[selected]', text: 'AIX'
    assert_select 'td', text: 'Jane Smith'
  end

  test "should require admin access for monthly report" do
    @request.session[:user_id] = 2 # Non-admin user
    role = Role.find(1)
    role.remove_permission!(:view_audit_reports) if role.permissions.include?(:view_audit_reports)
    get :monthly, params: { project_id: 1 }
    assert_response :forbidden
  end

  test "should handle empty monthly report data" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns([])
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1 }
    assert_response :success
    assert_select 'p.nodata', text: /No account data found/
  end

  test "should render error page on monthly service failure" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns(nil)
    service_mock.stubs(:success?).returns(false)
    service_mock.stubs(:errors).returns(['Invalid target system'])
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Report Generation Error'
    assert_select 'div.flash.error'
  end

  test "should export monthly report as CSV" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1, target_system: 'Oracle / SFMS' }, format: :csv
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_match /attachment/, response.headers['Content-Disposition']
    assert_match /monthly_report_oracle-sfms_.*\.csv/, response.headers['Content-Disposition']

    csv_content = response.body
    assert_match /Employee ID/, csv_content
    assert_match /Employee Name/, csv_content
    assert_match /John Doe/, csv_content
    assert_match /12345/, csv_content
    assert_match /active/, csv_content
  end

  test "should sort monthly report by each column" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      },
      {
        employee_id: '54321',
        employee_name: 'Jane Smith',
        status: 'inactive',
        account_action: 'Delete',
        closed_on: Date.today - 2.days,
        request_code: 'RC2',
        issue_id: 2
      }
    ]

    # Test sorting by employee_id
    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1, sort: 'employee_id' }
    assert_response :success
    assert_select 'table.list.issues tbody tr', count: 2
    assert_select 'td', text: 'John Doe'
    assert_select 'td', text: 'Jane Smith'
  end

  test "should export empty CSV for nil monthly report data" do
    service_mock = mock('service')
    service_mock.expects(:generate).returns(nil)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1 }, format: :csv
    assert_response :success
    assert_equal '', response.body
  end

  # Tests for mode and month parameters

  test "should default to monthly mode with current month" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        account_type: 'Oracle / SFMS',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    # Expect service to be called with beginning of current month
    expected_time = Date.current.beginning_of_month.in_time_zone

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)

    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |args|
      args[:target_system] == 'Oracle / SFMS' &&
        args[:as_of_time].to_date == expected_time.to_date
    end.returns(service_mock)

    get :monthly, params: { project_id: 1 }
    assert_response :success
  end

  test "should handle monthly mode with specific month" do
    mock_report_data = []
    month_num = 1
    year_num = 2026
    expected_time = Date.new(year_num, month_num, 1).beginning_of_month.in_time_zone

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)

    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |args|
      args[:target_system] == 'Oracle / SFMS' &&
        args[:as_of_time].to_date == expected_time.to_date
    end.returns(service_mock)

    get :monthly, params: { project_id: 1, mode: 'monthly', month: month_num, year: year_num }
    assert_response :success
  end

  test "should handle current mode showing latest state" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)

    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |args|
      args[:target_system] == 'Oracle / SFMS' &&
        args[:as_of_time].present?
    end.returns(service_mock)

    get :monthly, params: { project_id: 1, mode: 'current' }
    assert_response :success
  end

  test "should include month in CSV filename for monthly mode" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    month_num = 1
    year_num = 2026

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1, target_system: 'AIX', mode: 'monthly', month: month_num, year: year_num }, format: :csv
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_match /monthly_report_aix_202601\.csv/, response.headers['Content-Disposition']
  end

  test "should include current in CSV filename for current mode" do
    mock_report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      }
    ]

    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1, target_system: 'SFS', mode: 'current' }, format: :csv
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_match /monthly_report_sfs_current\.csv/, response.headers['Content-Disposition']
  end
end
