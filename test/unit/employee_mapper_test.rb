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
    assert_equal 'Personnel', result[:location]
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
end
