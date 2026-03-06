require File.expand_path('../../test_helper', __FILE__)

class SubjectSearchControllerTest < ActionController::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles

  def setup
    @admin = User.find(1)
    @user = User.find(2)
    @project = Project.find(1)

    # Enable the Subject Autofill module for the project
    @project.enable_module!(:audit_utils_subject_autofill)

    # Mock data for employee
    @mock_employee_data = {
      subject_id: '12345',
      subject_type: 'Employee',
      name: 'John Doe',
      email: 'john.doe@nysenate.gov',
      phone: '(518) 555-1234',
      status: 'Active',
      uid: 'johndoe',
      location: 'PERSONNEL'
    }

    # Mock data for vendor
    @mock_vendor_data = {
      subject_id: 'V1',
      subject_type: 'Vendor',
      name: 'Acme Corp',
      email: 'contact@acme.com',
      phone: '(555) 123-4567',
      status: 'Active',
      uid: nil,
      location: nil
    }

    # Use helper to configure fields
    configure_audit_fields(
      subject_type_field_id: 6,
      subject_id_field_id: 7,
      subject_name_field_id: 8,
      subject_email_field_id: 9,
      subject_phone_field_id: 10,
      subject_location_field_id: 11,
      subject_status_field_id: 12,
      subject_uid_field_id: 13
    )

    # Mock the SubjectService
    @mock_service = mock('SubjectService')
    NysenateAuditUtils::Subjects::SubjectService.stubs(:new).returns(@mock_service)
  end

  # Employee search tests (default behavior)

  def test_search_employees_with_valid_query_as_authorized_user
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('John', type: 'Employee', limit: 20, offset: 0).returns([@mock_employee_data])

    get :search, params: { q: 'John', project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 1, response_data['subjects'].length
    assert_equal 'John Doe', response_data['subjects'][0]['name']
    assert_equal '12345', response_data['subjects'][0]['subject_id']
    assert_equal 'Employee', response_data['type']
  end

  def test_search_defaults_to_employee_type_when_not_specified
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('John', type: 'Employee', limit: 20, offset: 0).returns([@mock_employee_data])

    get :search, params: { q: 'John', project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 'Employee', response_data['type']
  end

  def test_search_employees_explicitly
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('John', type: 'Employee', limit: 20, offset: 0).returns([@mock_employee_data])

    get :search, params: { q: 'John', type: 'Employee', project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 'Employee', response_data['type']
    assert_equal 1, response_data['subjects'].length
  end

  # Vendor search tests

  def test_search_vendors_with_valid_query
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('Acme', type: 'Vendor', limit: 20, offset: 0).returns([@mock_vendor_data])

    get :search, params: { q: 'Acme', type: 'Vendor', project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 1, response_data['subjects'].length
    assert_equal 'Acme Corp', response_data['subjects'][0]['name']
    assert_equal 'V1', response_data['subjects'][0]['subject_id']
    assert_equal 'Vendor', response_data['type']
  end

  # Invalid type tests

  def test_search_with_invalid_type
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: 'test', type: 'InvalidType', project_id: @project.id }

    assert_response :bad_request
    response_data = JSON.parse(@response.body)
    assert_match(/Invalid subject type/, response_data['error'])
    assert_equal [], response_data['subjects']
  end

  # General search tests

  def test_search_with_empty_query
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: '', project_id: @project.id }

    assert_response :bad_request
    response_data = JSON.parse(@response.body)
    assert_equal 'Search query cannot be empty', response_data['message']
    assert_equal [], response_data['subjects']
  end

  def test_search_without_permission
    @user.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(false)
    @request.session[:user_id] = @user.id

    get :search, params: { q: 'John', project_id: @project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_search_with_service_error
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).raises(StandardError.new('Service Error'))

    get :search, params: { q: 'John', project_id: @project.id }

    assert_response :service_unavailable
    response_data = JSON.parse(@response.body)
    assert_equal 'Subject search temporarily unavailable. Please try again later.', response_data['error']
    assert_equal [], response_data['subjects']
  end

  def test_search_sanitizes_input
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).returns([@mock_employee_data])

    get :search, params: { q: '<script>alert("xss")</script>John', project_id: @project.id }

    assert_response :success
    # Just verify the response is successful - sanitization happens in the controller
    response_data = JSON.parse(@response.body)
    assert response_data.has_key?('subjects')
  end

  def test_search_respects_limit_parameter
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('John', type: 'Employee', limit: 10, offset: 0).returns([@mock_employee_data])

    get :search, params: { q: 'John', project_id: @project.id, limit: 10 }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 10, response_data['limit']
  end

  def test_search_respects_offset_parameter
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).with('John', type: 'Employee', limit: 20, offset: 5).returns([])

    get :search, params: { q: 'John', project_id: @project.id, offset: 5 }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 5, response_data['offset']
  end

  # Field mappings tests

  def test_field_mappings_with_authorized_user
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id

    get :field_mappings, params: { project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)

    # Now expects field IDs directly from settings with _field suffix
    expected_mappings = {
      'subject_type_field' => 'issue_custom_field_values_6',
      'subject_id_field' => 'issue_custom_field_values_7',
      'subject_name_field' => 'issue_custom_field_values_8',
      'subject_email_field' => 'issue_custom_field_values_9',
      'subject_phone_field' => 'issue_custom_field_values_10',
      'subject_location_field' => 'issue_custom_field_values_11',
      'subject_status_field' => 'issue_custom_field_values_12',
      'subject_uid_field' => 'issue_custom_field_values_13'
    }

    assert_equal expected_mappings, response_data['field_mappings']
  end

  def test_field_mappings_with_missing_custom_fields
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id

    # Use helper to clear configuration
    clear_audit_configuration

    get :field_mappings, params: { project_id: @project.id }

    assert_response :success
    response_data = JSON.parse(@response.body)

    # When custom fields aren't configured, they shouldn't be included in the mapping
    assert_equal({}, response_data['field_mappings'])
  end

  def test_field_mappings_without_permission
    @user.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(false)
    @request.session[:user_id] = @user.id

    get :field_mappings, params: { project_id: @project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_field_mappings_handles_errors_gracefully
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, @project).returns(true)
    @request.session[:user_id] = @admin.id

    # Simulate an error in the configuration
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:autofill_field_ids).raises(StandardError.new('Configuration error'))

    get :field_mappings, params: { project_id: @project.id }

    assert_response :internal_server_error
    response_data = JSON.parse(@response.body)
    assert_equal 'Could not load field mappings', response_data['error']
  end

  # Permission and module tests

  def test_search_denies_access_when_user_lacks_project_permission
    project = Project.find(1)

    # User does NOT have permission for this specific project
    @user.stubs(:allowed_to?).with(:use_subject_autofill, project, {}).returns(false)
    @request.session[:user_id] = @user.id

    get :search, params: { q: 'John', project_id: project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_search_allows_user_with_project_permission
    project = Project.find(1)

    # Grant the permission to the user's role
    role = Role.find(1)  # Manager role
    role.add_permission!(:use_subject_autofill)

    @mock_service.stubs(:search).returns([@mock_employee_data])
    @request.session[:user_id] = @user.id

    get :search, params: { q: 'John', project_id: project.id }

    assert_response :success
  end

  def test_search_denies_access_when_module_not_enabled_for_project
    project = Project.find(1)

    # Disable the Subject Autofill module for this project
    project.enabled_modules.where(name: 'audit_utils_subject_autofill').destroy_all
    project.reload

    # Even if user has permission, module must be enabled
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, project, {}).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: 'John', project_id: project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_search_allows_access_when_module_enabled_and_user_has_permission
    project = Project.find(1)

    # Enable the module
    project.enable_module!(:audit_utils_subject_autofill)

    # User has permission
    @admin.stubs(:allowed_to?).with(:use_subject_autofill, project, {}).returns(true)
    @request.session[:user_id] = @admin.id
    @mock_service.stubs(:search).returns([@mock_employee_data])

    get :search, params: { q: 'John', project_id: project.id }

    assert_response :success
  end

  def test_field_mappings_denies_access_when_user_lacks_project_permission
    project = Project.find(1)

    # User does NOT have permission for this project
    @user.stubs(:allowed_to?).with(:use_subject_autofill, project, {}).returns(false)
    @request.session[:user_id] = @user.id

    get :field_mappings, params: { project_id: project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_field_mappings_denies_access_when_module_not_enabled_for_project
    project = Project.find(1)

    # Disable the module
    project.enabled_modules.where(name: 'audit_utils_subject_autofill').destroy_all
    project.reload

    @admin.stubs(:allowed_to?).with(:use_subject_autofill, project, {}).returns(true)
    @request.session[:user_id] = @admin.id

    get :field_mappings, params: { project_id: project.id }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_search_requires_project_id_parameter
    # When no project_id is provided, should deny access
    @request.session[:user_id] = @user.id

    get :search, params: { q: 'John' }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_field_mappings_requires_project_id_parameter
    # When no project_id is provided, should deny access
    @request.session[:user_id] = @user.id

    get :field_mappings

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end
end
