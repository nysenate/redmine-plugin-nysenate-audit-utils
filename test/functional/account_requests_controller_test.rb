# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class AccountRequestsControllerTest < ActionController::TestCase
  fixtures :users, :roles, :projects, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :members, :member_roles, :enabled_modules, :custom_fields

  def setup
    @request.session[:user_id] = 1 # admin
    @project = Project.find(1)
    @project.enable_module!(:audit_utils)
  end

  def stub_employee
    OpenStruct.new(employee_id: 12345, display_name: 'John Doe')
  end

  test "redirects to prefilled new issue form when employee is found" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(stub_employee)
    NysenateAuditUtils::Autofill::EmployeeMapper
      .stubs(:map_employee_to_field_values).returns(2 => 'jdoe')

    get :new, params: { project_id: @project.id, employee_id: '12345' }

    assert_response :redirect
    assert_match %r{/projects/#{@project.identifier}/issues/new}, @response.location
    # Prefilled custom field value rides along in the redirect query string
    assert_match(/jdoe/, @response.location)
    assert_nil flash[:warning]
  end

  test "redirects to blank new issue form with a warning when employee is missing" do
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).returns(nil)

    get :new, params: { project_id: @project.id, employee_id: 'bogus' }

    assert_response :redirect
    assert_match %r{/projects/#{@project.identifier}/issues/new}, @response.location
    assert_not_nil flash[:warning]
  end

  test "returns 403 when the user cannot add issues" do
    # Non-admin member whose role lacks :add_issues
    @request.session[:user_id] = 2
    Role.find(1).remove_permission!(:add_issues)

    get :new, params: { project_id: @project.id, employee_id: '12345' }

    assert_response :forbidden
  end

  test "returns 403 when the audit_utils module is not enabled" do
    @project.disable_module!(:audit_utils)

    get :new, params: { project_id: @project.id, employee_id: '12345' }

    assert_response :forbidden
  end

  test "returns 404 for an unknown project" do
    get :new, params: { project_id: 999999, employee_id: '12345' }

    assert_response :not_found
  end
end
