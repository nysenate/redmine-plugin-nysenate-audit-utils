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
end
