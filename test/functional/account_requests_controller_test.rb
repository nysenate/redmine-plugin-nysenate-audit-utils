# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AccountRequestsControllerTest < Redmine::ControllerTest
  fixtures :users, :roles, :projects, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :members, :member_roles, :enabled_modules, :custom_fields

  def setup
    set_tmp_attachments_directory
    @request.session[:user_id] = 1 # admin
    @project = Project.find(1)
    @project.enable_module!(:audit_utils)
    @from = (Date.today - 1).to_time
    @to = Date.today.to_time
  end

  def stub_employee
    OpenStruct.new(
      employee_id: 12345, display_name: 'John Doe', email: 'john@nysenate.gov',
      work_phone: '555-1234', active: true, uid: 'jdoe', resp_center_head: nil
    )
  end

  # Stub the daily report service so a CSV gets generated for the attachment.
  def stub_report(success: true, rows: [{ user_id: 12345 }])
    service = mock('daily_report_service')
    service.stubs(:generate).returns(rows)
    service.stubs(:success?).returns(success)
    NysenateAuditUtils::Reporting::DailyReportService.stubs(:new).returns(service)
    NysenateAuditUtils::Reporting::CsvGenerator.stubs(:generate_daily_csv).returns("a,b\n1,2\n")
  end

  def get_new(extra = {})
    get :new, params: {
      project_id: @project.id, employee_id: '12345',
      from_date: @from.iso8601, to_date: @to.iso8601
    }.merge(extra)
  end

  test "renders the prefilled new issue form and seeds the daily report attachment" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    stub_report

    assert_difference 'Attachment.count', 1 do
      get_new
    end

    assert_response :success
    assert_select 'input#issue_subject' # the new issue form rendered

    # The created attachment is container-less (tokenable)
    attachment = Attachment.order(:id).last
    assert_nil attachment.container
    assert_equal "daily_report_#{@to.to_date.strftime('%Y%m%d')}.csv", attachment.filename

    # Core renders it natively as a pending attachment: filename + submittable token
    assert_select "input[name=?][value=?]", 'attachments[p0][filename]', attachment.filename
    assert_select "input[type=hidden][name=?]", 'attachments[p0][token]'
    assert_select 'div.flash.warning', false
  end

  test "removal mode prefills subject and description with the request code" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    NysenateAuditUtils::RequestCodes::RequestCodeMapper.any_instance.stubs(:get_request_code)
      .with('Delete', 'AIX').returns('AIXI')
    stub_report

    assert_difference 'Attachment.count', 1 do
      get_new(target_system: 'AIX', account_action: 'Delete')
    end

    assert_response :success
    assert_select 'input#issue_subject[value=?]', 'AIXI: Remove AIX account for John Doe'
    assert_select 'textarea#issue_description', 'Remove AIX account for John Doe'
    # The daily report is still seeded as a pending attachment
    assert_select "input[type=hidden][name=?]", 'attachments[p0][token]'
  end

  test "removal mode omits the code prefix when no request code is configured" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    NysenateAuditUtils::RequestCodes::RequestCodeMapper.any_instance.stubs(:get_request_code).returns(nil)
    stub_report

    get_new(target_system: 'AIX', account_action: 'Delete')

    assert_response :success
    assert_select 'input#issue_subject[value=?]', 'Remove AIX account for John Doe'
  end

  test "removal mode renders the overridable related-issue field seeded with the granting ticket" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    NysenateAuditUtils::RequestCodes::RequestCodeMapper.any_instance.stubs(:get_request_code).returns(nil)
    stub_report

    get_new(target_system: 'AIX', account_action: 'Delete', related_issue_id: '42')

    assert_response :success
    assert_select 'p#related-issue-field' do
      assert_select 'select#related_relation_type'
      assert_select 'input#related_issue_id[value=?]', '42'
    end
  end

  test "does not render the related-issue field without a related_issue_id" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    stub_report

    get_new

    assert_response :success
    assert_select 'p#related-issue-field', false
  end

  test "renders a blank form with a warning when the employee is missing" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).returns(nil)

    assert_no_difference 'Attachment.count' do
      get_new(employee_id: 'bogus')
    end

    assert_response :success
    assert_select 'input#issue_subject'
    assert_select 'div.flash.warning'
    assert_select "input[name=?]", 'attachments[p0][token]', false # nothing seeded
  end

  test "renders the form without an attachment when report generation fails" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).returns(stub_employee)
    stub_report(success: false)

    assert_no_difference 'Attachment.count' do
      get_new
    end

    assert_response :success
    assert_select "input[name=?]", 'attachments[p0][token]', false
  end

  test "returns 403 when the user cannot add issues" do
    @request.session[:user_id] = 2
    Role.find(1).remove_permission!(:add_issues)

    get_new
    assert_response :forbidden
  end

  test "returns 403 when the audit_utils module is not enabled" do
    @project.disable_module!(:audit_utils)

    get_new
    assert_response :forbidden
  end

  test "returns 404 for an unknown project" do
    get :new, params: { project_id: 999999, employee_id: '12345' }
    assert_response :not_found
  end
end
