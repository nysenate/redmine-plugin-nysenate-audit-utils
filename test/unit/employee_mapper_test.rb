require File.expand_path('../../test_helper', __FILE__)

class EmployeeMapperTest < ActiveSupport::TestCase
  fixtures :custom_fields

  def setup
    # Mock plugin settings with field IDs instead of names - use string keys
    @mock_settings = {
      'user_type_field_id' => 1,
      'user_id_field_id' => 2,
      'user_name_field_id' => 3,
      'user_email_field_id' => 4,
      'user_phone_field_id' => 5,
      'user_location_field_id' => 6,
      'user_status_field_id' => 7,
      'user_uid_field_id' => 8
    }

    Setting.stubs(:plugin_nysenate_audit_utils).returns(@mock_settings)
  end

  def test_map_employee_with_complete_data
    resp_center_head = OpenStruct.new(code: 'PERSONNEL', short_name: 'Personnel')
    employee = OpenStruct.new(
      employee_id: 12345,
      display_name: 'John Doe',
      email: 'john.doe@nysenate.gov',
      work_phone: '(518) 555-1234',
      active: true,
      uid: 'jdoe',
      resp_center_head: resp_center_head
    )

    result = NysenateAuditUtils::Autofill::EmployeeMapper.map_employee(employee)

    assert_equal 12345, result[:employee_id]
    assert_equal 'John Doe', result[:name]
    assert_equal 'john.doe@nysenate.gov', result[:email]
    assert_equal '(518) 555-1234', result[:phone]
    assert_equal 'Active', result[:status]
    assert_equal 'jdoe', result[:uid]
    assert_equal 'PERSONNEL', result[:location]
    assert_equal resp_center_head, result[:resp_center_head]
  end

  def test_map_employee_with_missing_data
    employee = OpenStruct.new(
      employee_id: nil,
      display_name: nil,
      email: nil,
      work_phone: nil,
      active: false,
      uid: nil,
      resp_center_head: nil
    )

    result = NysenateAuditUtils::Autofill::EmployeeMapper.map_employee(employee)

    assert_nil result[:employee_id]
    assert_nil result[:name]
    assert_nil result[:email]
    assert_nil result[:phone]
    assert_equal 'Inactive', result[:status]
    assert_nil result[:uid]
    assert_nil result[:location]
    assert_nil result[:resp_center_head]
  end

  def test_get_field_mappings
    # Now returns field IDs from CustomFieldConfiguration
    mappings = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

    assert_equal 1, mappings[:user_type]
    assert_equal 2, mappings[:user_id]
    assert_equal 3, mappings[:user_name]
    assert_equal 4, mappings[:user_email]
    assert_equal 5, mappings[:user_phone]
    assert_equal 6, mappings[:user_location]
    assert_equal 7, mappings[:user_status]
    assert_equal 8, mappings[:user_uid]
  end

  def test_get_field_id_with_existing_field
    # Use CustomFieldConfiguration directly
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_id_field_id')
    assert_equal 2, field_id
  end

  def test_get_field_id_with_non_existing_field
    # Clear the mock setting for this test
    Setting.stubs(:plugin_nysenate_audit_utils).returns({})

    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_id_field_id')
    assert_nil field_id
  end

  def test_map_employee_to_field_values_keys_by_configured_field_id
    resp_center_head = OpenStruct.new(code: 'PERSONNEL', short_name: 'Personnel')
    employee = OpenStruct.new(
      employee_id: 12345,
      display_name: 'John Doe',
      email: 'john.doe@nysenate.gov',
      work_phone: '(518) 555-1234',
      active: true,
      uid: 'jdoe',
      resp_center_head: resp_center_head
    )

    values = NysenateAuditUtils::Autofill::EmployeeMapper.map_employee_to_field_values(employee)

    # Keyed by the configured custom field IDs from @mock_settings
    assert_equal 12345, values[2]                    # user_id
    assert_equal 'John Doe', values[3]               # user_name
    assert_equal 'john.doe@nysenate.gov', values[4]  # user_email
    assert_equal '(518) 555-1234', values[5]         # user_phone
    assert_equal 'PERSONNEL', values[6]              # user_location
    assert_equal 'Active', values[7]                 # user_status
    assert_equal 'jdoe', values[8]                   # user_uid
    # Daily report is always employees -> Account Holder Type fixed to 'Employee'
    assert_equal 'Employee', values[1]               # user_type
  end

  def test_map_employee_to_field_values_skips_unconfigured_fields
    # Only user_id and user_name are configured
    Setting.stubs(:plugin_nysenate_audit_utils).returns(
      'user_id_field_id' => 2,
      'user_name_field_id' => 3
    )

    employee = OpenStruct.new(
      employee_id: 999,
      display_name: 'Jane Roe',
      email: 'jane@nysenate.gov',
      work_phone: nil,
      active: true,
      uid: 'jroe',
      resp_center_head: nil
    )

    values = NysenateAuditUtils::Autofill::EmployeeMapper.map_employee_to_field_values(employee)

    assert_equal({ 2 => 999, 3 => 'Jane Roe' }, values)
  end

  def test_map_removal_field_values_sets_target_system_and_delete_action
    Setting.stubs(:plugin_nysenate_audit_utils).returns(
      @mock_settings.merge(
        'target_system_field_id' => 20,
        'account_action_field_id' => 21
      )
    )

    employee = OpenStruct.new(
      employee_id: 12345, display_name: 'John Doe', email: 'john@nysenate.gov',
      work_phone: nil, active: true, uid: 'jdoe', resp_center_head: nil
    )

    values = NysenateAuditUtils::Autofill::EmployeeMapper.map_removal_field_values(employee, target_system: 'AIX')

    assert_equal 12345, values[2]        # Account Holder fields still present
    assert_equal 'John Doe', values[3]
    assert_equal 'AIX', values[20]       # Target System
    assert_equal 'Delete', values[21]    # Account Action
  end

  def test_map_removal_field_values_skips_unconfigured_target_and_action_fields
    # Neither target_system nor account_action field is configured
    Setting.stubs(:plugin_nysenate_audit_utils).returns(
      'user_id_field_id' => 2,
      'user_name_field_id' => 3
    )

    employee = OpenStruct.new(
      employee_id: 999, display_name: 'Jane Roe', email: nil,
      work_phone: nil, active: true, uid: 'jroe', resp_center_head: nil
    )

    values = NysenateAuditUtils::Autofill::EmployeeMapper.map_removal_field_values(employee, target_system: 'SFS')

    assert_equal({ 2 => 999, 3 => 'Jane Roe' }, values)
  end
end
