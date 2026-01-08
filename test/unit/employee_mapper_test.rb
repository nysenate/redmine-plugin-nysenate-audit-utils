require File.expand_path('../../test_helper', __FILE__)

class EmployeeMapperTest < ActiveSupport::TestCase
  fixtures :custom_fields

  def setup
    # Mock plugin settings with field IDs instead of names - use string keys
    @mock_settings = {
      'employee_id_field_id' => 1,
      'employee_name_field_id' => 2,
      'employee_email_field_id' => 3,
      'employee_phone_field_id' => 4,
      'employee_office_field_id' => 5,
      'employee_status_field_id' => 6,
      'employee_uid_field_id' => 7
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
    assert_equal 'Personnel', result[:office]
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
    assert_nil result[:office]
    assert_nil result[:resp_center_head]
  end

  def test_get_field_mappings
    # Now returns field IDs from CustomFieldConfiguration
    mappings = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

    assert_equal 1, mappings[:employee_id]
    assert_equal 2, mappings[:employee_name]
    assert_equal 3, mappings[:employee_email]
    assert_equal 4, mappings[:employee_phone]
    assert_equal 5, mappings[:employee_office]
    assert_equal 6, mappings[:employee_status]
    assert_equal 7, mappings[:employee_uid]
  end

  def test_get_field_id_with_existing_field
    # Use CustomFieldConfiguration directly
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_id_field_id')
    assert_equal 1, field_id
  end

  def test_get_field_id_with_non_existing_field
    # Clear the mock setting for this test
    Setting.stubs(:plugin_nysenate_audit_utils).returns({})

    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_id_field_id')
    assert_nil field_id
  end
end
