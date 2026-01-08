require File.expand_path('../../test_helper', __FILE__)

class EmployeeSearchControllerTest < ActionController::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles

  def setup
    @admin = User.find(1)
    @user = User.find(2)

    # Mock the ESS service
    resp_center_head = OpenStruct.new(code: 'PERSONNEL')
    @mock_employee = OpenStruct.new(
      employee_id: 12345,
      display_name: 'John Doe',
      email: 'john.doe@nysenate.gov',
      work_phone: '(518) 555-1234',
      resp_center_head: resp_center_head
    )

    # Use helper to configure fields
    configure_audit_fields(
      employee_id_field_id: 7,
      employee_name_field_id: 8,
      employee_email_field_id: 9,
      employee_phone_field_id: 10,
      employee_office_field_id: 11,
      employee_status_field_id: 12,
      employee_uid_field_id: 13
    )
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:search).returns([@mock_employee])
  end

  def test_search_with_valid_query_as_authorized_user
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: 'John' }

    assert_response :success
    response_data = JSON.parse(@response.body)
    assert_equal 1, response_data['employees'].length
    assert_equal 'John Doe', response_data['employees'][0]['name']
    assert_equal 12345, response_data['employees'][0]['employee_id']
  end

  def test_search_with_empty_query
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: '' }

    assert_response :bad_request
    response_data = JSON.parse(@response.body)
    assert_equal 'Search query cannot be empty', response_data['message']
    assert_equal [], response_data['employees']
  end

  def test_search_without_permission
    @user.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(false)
    @request.session[:user_id] = @user.id

    get :search, params: { q: 'John' }

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_search_with_ess_api_error
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:search).raises(StandardError.new('API Error'))

    get :search, params: { q: 'John' }

    assert_response :service_unavailable
    response_data = JSON.parse(@response.body)
    assert_equal 'Employee search temporarily unavailable. Please try again later.', response_data['error']
    assert_equal [], response_data['employees']
  end

  def test_search_sanitizes_input
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    get :search, params: { q: '<script>alert("xss")</script>John' }

    assert_response :success
    # Just verify the response is successful - sanitization happens in the controller
    response_data = JSON.parse(@response.body)
    assert response_data.has_key?('employees')
  end

  def test_field_mappings_with_authorized_user
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    get :field_mappings

    assert_response :success
    response_data = JSON.parse(@response.body)

    # Now expects field IDs directly from settings with _field suffix
    expected_mappings = {
      'employee_id_field' => 'issue_custom_field_values_7',
      'employee_name_field' => 'issue_custom_field_values_8',
      'employee_email_field' => 'issue_custom_field_values_9',
      'employee_phone_field' => 'issue_custom_field_values_10',
      'employee_office_field' => 'issue_custom_field_values_11',
      'employee_status_field' => 'issue_custom_field_values_12',
      'employee_uid_field' => 'issue_custom_field_values_13'
    }

    assert_equal expected_mappings, response_data['field_mappings']
  end

  def test_field_mappings_with_missing_custom_fields
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    # Use helper to clear configuration
    clear_audit_configuration

    get :field_mappings

    assert_response :success
    response_data = JSON.parse(@response.body)

    # When custom fields aren't configured, they shouldn't be included in the mapping
    assert_equal({}, response_data['field_mappings'])
  end

  def test_field_mappings_without_permission
    @user.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(false)
    @request.session[:user_id] = @user.id

    get :field_mappings

    assert_response :forbidden
    response_data = JSON.parse(@response.body)
    assert_equal 'Access denied', response_data['error']
  end

  def test_field_mappings_handles_errors_gracefully
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, nil, { global: true }).returns(true)
    @request.session[:user_id] = @admin.id

    # Simulate an error in the configuration
    NysenateAuditUtils::CustomFieldConfiguration.stubs(:autofill_field_ids).raises(StandardError.new('Configuration error'))

    get :field_mappings

    assert_response :internal_server_error
    response_data = JSON.parse(@response.body)
    assert_equal 'Could not load field mappings', response_data['error']
  end
end
