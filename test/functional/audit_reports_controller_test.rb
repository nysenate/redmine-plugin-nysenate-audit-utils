require File.expand_path('../../test_helper', __FILE__)

class AuditReportsControllerTest < ActionController::TestCase
  fixtures :users, :roles, :issues, :projects, :trackers, :issue_statuses, :enumerations, :members, :member_roles, :enabled_modules

  def setup
    @request.session[:user_id] = 1 # Admin user
    @project = Project.find(1)
    @project.enable_module!(:audit_utils)

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
        user_name: 'John Doe',
        ticket_count: 2,
        ticket_url: '/issues?cf_1=12345',
        transaction_codes: 'APP',
        phone_number: '555-1234',
        office: 'IT',
        office_location: nil,
        user_id: '12345',
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
    assert_select 'p.nodata', text: /No user status changes found/
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
    assert_select 'p.nodata', text: /No user status changes found/
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
        user_name: 'John Doe',
        ticket_count: 2,
        ticket_url: '/issues?cf_1=12345',
        transaction_codes: 'APP',
        phone_number: '555-1234',
        office: 'IT',
        office_location: nil,
        user_id: '12345',
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
    assert_match /Account Holder Name/, csv_content
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

  def weekly_mock_data
    [
      {
        issue_id: 1,
        subject: 'Test Issue 1',
        status: 'Closed',
        user_id: '12345',
        user_uid: 'johndoe',
        user_name: 'John Doe',
        office: 'Senate Office A',
        request_code: 'RC1',
        updated_on: Time.current,
        created_on: Time.current - 5.days,
        closed_on: Time.current - 1.day
      },
      {
        issue_id: 2,
        subject: 'Test Issue 2',
        status: 'Closed',
        user_id: '54321',
        user_uid: 'janesmith',
        user_name: 'Jane Smith',
        office: 'Personnel',
        request_code: 'RC2',
        updated_on: Time.current - 1.day,
        created_on: Time.current - 6.days,
        closed_on: Time.current - 2.days
      }
    ]
  end

  def stub_weekly_service(report_data, from_date: nil, to_date: nil, success: true, errors: [])
    from_date ||= Date.current.beginning_of_week(:sunday).in_time_zone - 7.days
    to_date ||= Date.current.beginning_of_week(:sunday).in_time_zone
    service_mock = mock('service')
    service_mock.expects(:generate).returns(report_data)
    service_mock.stubs(:from_date).returns(from_date)
    service_mock.stubs(:to_date).returns(to_date)
    service_mock.stubs(:success?).returns(success)
    service_mock.stubs(:errors).returns(errors)
    NysenateAuditUtils::Reporting::WeeklyReportService.expects(:new).returns(service_mock)
    service_mock
  end

  test "should get weekly report" do
    stub_weekly_service(weekly_mock_data)

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Weekly Report'
    assert_select 'table.list.issues'
    assert_select 'td', text: 'Test Issue 1'
    assert_select 'td', text: 'Test Issue 2'
  end

  test "should render new weekly columns" do
    stub_weekly_service(weekly_mock_data)

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'td', text: 'John Doe'
    assert_select 'td', text: 'Senate Office A'
    assert_select 'th a', text: 'Account Holder Name'
    assert_select 'th a', text: 'Account Holder Office'
    assert_select 'th a', text: 'Open Date'
    assert_select 'th a', text: 'Close Date'
  end

  test "should display date range inputs" do
    stub_weekly_service(weekly_mock_data)

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'input[name=start_date][type=date]'
    assert_select 'input[name=end_date][type=date]'
  end

  test "should not display status filter dropdown" do
    stub_weekly_service(weekly_mock_data)

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'select[name=status_filter]', count: 0
  end

  test "should pass date range to weekly service" do
    NysenateAuditUtils::Reporting::WeeklyReportService.expects(:new).with do |args|
      args[:from_date].present? && args[:to_date].present?
    end.returns(stub_returning_service(weekly_mock_data))

    get :weekly, params: { project_id: 1, start_date: '2026-03-29', end_date: '2026-04-05' }
    assert_response :success
  end

  test "should require admin access for weekly report" do
    @request.session[:user_id] = 2 # Non-admin user
    role = Role.find(1)
    role.remove_permission!(:view_audit_reports) if role.permissions.include?(:view_audit_reports)
    get :weekly, params: { project_id: 1 }
    assert_response :forbidden
  end

  test "should handle empty weekly report data" do
    stub_weekly_service([])

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'p.nodata', text: /No closed tickets found/
  end

  test "should render error page on weekly service failure" do
    stub_weekly_service(nil, success: false, errors: ['Custom field configuration error'])

    get :weekly, params: { project_id: 1 }
    assert_response :success
    assert_select 'h2', text: 'Report Generation Error'
    assert_select 'div.flash.error'
  end

  test "should export weekly report as CSV" do
    stub_weekly_service(weekly_mock_data)

    get :weekly, params: { project_id: 1 }, format: :csv
    assert_response :success
    assert_equal 'text/csv; header=present', response.content_type
    assert_match /weekly_report_.*\.csv/, response.headers['Content-Disposition']

    csv_content = response.body
    assert_match /Ticket #/, csv_content
    assert_match /Account Holder Name/, csv_content
    assert_match /Account Holder Username/, csv_content
    assert_match /Account Holder ID/, csv_content
    assert_match /Account Holder Office/, csv_content
    assert_match /Open Date/, csv_content
    assert_match /Close Date/, csv_content
    assert_match /Request Code/, csv_content
    assert_match /Test Issue 1/, csv_content
    assert_match /12345/, csv_content
    assert_match /John Doe/, csv_content
    assert_match /Senate Office A/, csv_content
  end

  test "should get monthly report with default system" do
    mock_report_data = [
      {
        user_id: '12345',
        user_name: 'John Doe',
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
        user_id: '54321',
        user_name: 'Jane Smith',
        account_type: 'AIX',
        status: 'inactive',
        account_action: 'Delete',
        closed_on: Date.today - 2.days,
        request_code: 'RC2',
        issue_id: 2
      }
    ]

    # Mock the target system field to include AIX in possible values
    target_system_field_mock = mock('target_system_field')
    target_system_field_mock.stubs(:possible_values).returns(['Oracle / SFMS', 'SFS', 'AIX', 'NYSDS', 'PayServ', 'OGS Swiper Access'])
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:target_system_field).returns(target_system_field_mock)

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
        user_id: '12345',
        user_name: 'John Doe',
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
    assert_match /Account Holder ID/, csv_content
    assert_match /Account Holder Name/, csv_content
    assert_match /John Doe/, csv_content
    assert_match /12345/, csv_content
    assert_match /active/, csv_content
  end

  test "should sort monthly report by each column" do
    mock_report_data = [
      {
        user_id: '12345',
        user_name: 'John Doe',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.today - 1.day,
        request_code: 'RC1',
        issue_id: 1
      },
      {
        user_id: '54321',
        user_name: 'Jane Smith',
        status: 'inactive',
        account_action: 'Delete',
        closed_on: Date.today - 2.days,
        request_code: 'RC2',
        issue_id: 2
      }
    ]

    # Test sorting by user_id
    service_mock = mock('service')
    service_mock.expects(:generate).returns(mock_report_data)
    service_mock.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).returns(service_mock)

    get :monthly, params: { project_id: 1, sort: 'user_id' }
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
        user_id: '12345',
        user_name: 'John Doe',
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
        user_id: '12345',
        user_name: 'John Doe',
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
        user_id: '12345',
        user_name: 'John Doe',
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
        user_id: '12345',
        user_name: 'John Doe',
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

  # Tests for monthly_zip action

  test "should export all systems as ZIP in current mode" do
    target_system_field_mock = mock('target_system_field')
    target_system_field_mock.stubs(:possible_values).returns(['Oracle / SFMS', 'AIX'])
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:target_system_field).returns(target_system_field_mock)

    oracle_data = [{ user_id: '111', user_name: 'Alice', status: 'active', account_action: 'Add', closed_on: Date.today, request_code: 'OAA', issue_id: 1 }]
    aix_data    = [{ user_id: '222', user_name: 'Bob',   status: 'active', account_action: 'Add', closed_on: Date.today, request_code: 'AAA', issue_id: 2 }]

    oracle_svc = mock('oracle_service')
    oracle_svc.expects(:generate).returns(oracle_data)
    oracle_svc.stubs(:success?).returns(true)

    aix_svc = mock('aix_service')
    aix_svc.expects(:generate).returns(aix_data)
    aix_svc.stubs(:success?).returns(true)

    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with { |a| a[:target_system] == 'Oracle / SFMS' }.returns(oracle_svc)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with { |a| a[:target_system] == 'AIX' }.returns(aix_svc)

    get :monthly_zip, params: { project_id: 1, mode: 'current' }
    assert_response :success
    assert_equal 'application/zip', response.content_type
    assert_match /attachment/, response.headers['Content-Disposition']
    assert_match /monthly_reports_all_systems_current\.zip/, response.headers['Content-Disposition']

    zip_content = response.body
    assert zip_content.length > 0

    Zip::InputStream.open(StringIO.new(zip_content)) do |zip|
      entries = []
      while (entry = zip.get_next_entry)
        entries << entry.name
      end
      assert_includes entries, 'monthly_report_oracle-sfms_current.csv'
      assert_includes entries, 'monthly_report_aix_current.csv'
    end
  end

  test "should export all systems as ZIP in monthly mode" do
    target_system_field_mock = mock('target_system_field')
    target_system_field_mock.stubs(:possible_values).returns(['Oracle / SFMS'])
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:target_system_field).returns(target_system_field_mock)

    oracle_data = [{ user_id: '111', user_name: 'Alice', status: 'active', account_action: 'Add', closed_on: Date.today, request_code: 'OAA', issue_id: 1 }]
    svc = mock('service')
    svc.expects(:generate).returns(oracle_data)
    svc.stubs(:success?).returns(true)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with do |a|
      a[:target_system] == 'Oracle / SFMS' && a[:as_of_time].to_date == Date.new(2026, 3, 1)
    end.returns(svc)

    get :monthly_zip, params: { project_id: 1, mode: 'monthly', month: 3, year: 2026 }
    assert_response :success
    assert_equal 'application/zip', response.content_type
    assert_match /monthly_reports_all_systems_202603\.zip/, response.headers['Content-Disposition']
  end

  test "should skip failed systems in ZIP export and still succeed" do
    target_system_field_mock = mock('target_system_field')
    target_system_field_mock.stubs(:possible_values).returns(['Oracle / SFMS', 'AIX'])
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:target_system_field).returns(target_system_field_mock)

    oracle_data = [{ user_id: '111', user_name: 'Alice', status: 'active', account_action: 'Add', closed_on: Date.today, request_code: 'OAA', issue_id: 1 }]
    oracle_svc = mock('oracle_service')
    oracle_svc.expects(:generate).returns(oracle_data)
    oracle_svc.stubs(:success?).returns(true)

    aix_svc = mock('aix_service')
    aix_svc.expects(:generate).returns(nil)
    aix_svc.stubs(:success?).returns(false)
    aix_svc.stubs(:errors).returns(['Invalid system'])

    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with { |a| a[:target_system] == 'Oracle / SFMS' }.returns(oracle_svc)
    NysenateAuditUtils::Reporting::MonthlyReportService.expects(:new).with { |a| a[:target_system] == 'AIX' }.returns(aix_svc)

    get :monthly_zip, params: { project_id: 1, mode: 'current' }
    assert_response :success
    assert_equal 'application/zip', response.content_type

    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      entries = []
      while (entry = zip.get_next_entry)
        entries << entry.name
      end
      assert_includes entries, 'monthly_report_oracle-sfms_current.csv'
      assert_not_includes entries, 'monthly_report_aix_current.csv'
    end
  end

  test "should require view_audit_reports permission for monthly_zip" do
    @request.session[:user_id] = 2
    role = Role.find(1)
    role.remove_permission!(:view_audit_reports) if role.permissions.include?(:view_audit_reports)
    get :monthly_zip, params: { project_id: 1 }
    assert_response :forbidden
  end

  private

  # Returns a simple service mock that generates report_data and succeeds.
  # Used in tests that verify service params via .expects(:new).with { ... }
  def stub_returning_service(report_data)
    svc = mock('service')
    svc.expects(:generate).returns(report_data)
    svc.stubs(:from_date).returns(Date.current.beginning_of_week(:sunday).in_time_zone - 7.days)
    svc.stubs(:to_date).returns(Date.current.beginning_of_week(:sunday).in_time_zone)
    svc.stubs(:success?).returns(true)
    svc.stubs(:errors).returns([])
    svc
  end
end
