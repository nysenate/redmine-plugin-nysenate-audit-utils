# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class CustomFieldConfigurationTest < ActiveSupport::TestCase
  def setup
    # Mock plugin settings - use string keys as Redmine does
    @mock_settings = {
      'employee_id_field_id' => 1,
      'employee_name_field_id' => 2,
      'account_action_field_id' => 3,
      'target_system_field_id' => 4
    }

    Setting.stubs(:plugin_nysenate_audit_utils).returns(@mock_settings)
  end

  def test_get_field_id_with_configured_field
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_id_field_id')
    assert_equal 1, field_id
  end

  def test_get_field_id_with_unconfigured_field
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_office_field_id')
    assert_nil field_id
  end

  def test_all_field_ids
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.all_field_ids

    assert_equal 1, field_ids['employee_id_field_id']
    assert_equal 2, field_ids['employee_name_field_id']
    assert_equal 3, field_ids['account_action_field_id']
    assert_equal 4, field_ids['target_system_field_id']
    assert_nil field_ids['employee_office_field_id']
  end

  def test_employee_id_field_id
    assert_equal 1, NysenateAuditUtils::CustomFieldConfiguration.employee_id_field_id
  end

  def test_account_action_field_id
    assert_equal 3, NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
  end

  def test_target_system_field_id
    assert_equal 4, NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
  end

  def test_autofill_field_ids
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

    assert_equal 1, field_ids[:employee_id]
    assert_equal 2, field_ids[:employee_name]
    assert_nil field_ids[:employee_email] # Not configured
  end

  def test_validate_with_all_required_fields
    # Mock all required fields as configured (all 9 fields)
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'employee_id_field_id' => 1,
      'employee_name_field_id' => 2,
      'employee_email_field_id' => 3,
      'employee_phone_field_id' => 4,
      'employee_status_field_id' => 5,
      'employee_uid_field_id' => 6,
      'employee_office_field_id' => 7,
      'account_action_field_id' => 8,
      'target_system_field_id' => 9
    })

    # Mock custom fields exist for each ID
    CustomField.stubs(:find_by).with(id: 1, type: 'IssueCustomField').returns(CustomField.new(id: 1, name: 'Employee ID'))
    CustomField.stubs(:find_by).with(id: 2, type: 'IssueCustomField').returns(CustomField.new(id: 2, name: 'Employee Name'))
    CustomField.stubs(:find_by).with(id: 3, type: 'IssueCustomField').returns(CustomField.new(id: 3, name: 'Employee Email'))
    CustomField.stubs(:find_by).with(id: 4, type: 'IssueCustomField').returns(CustomField.new(id: 4, name: 'Employee Phone'))
    CustomField.stubs(:find_by).with(id: 5, type: 'IssueCustomField').returns(CustomField.new(id: 5, name: 'Employee Status'))
    CustomField.stubs(:find_by).with(id: 6, type: 'IssueCustomField').returns(CustomField.new(id: 6, name: 'Employee UID'))
    CustomField.stubs(:find_by).with(id: 7, type: 'IssueCustomField').returns(CustomField.new(id: 7, name: 'Employee Office'))
    CustomField.stubs(:find_by).with(id: 8, type: 'IssueCustomField').returns(CustomField.new(id: 8, name: 'Account Action'))
    CustomField.stubs(:find_by).with(id: 9, type: 'IssueCustomField').returns(CustomField.new(id: 9, name: 'Target System'))

    errors = NysenateAuditUtils::CustomFieldConfiguration.validate
    assert_empty errors
  end

  def test_validate_with_missing_required_field
    # Mock missing employee_id field
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'account_action_field_id' => 2,
      'target_system_field_id' => 3
    })

    errors = NysenateAuditUtils::CustomFieldConfiguration.validate
    assert_includes errors, "Required field 'Employee ID' (employee_id_field_id) is not configured"
  end

  def test_valid_with_complete_configuration
    # Mock all required fields as configured (all 9 fields)
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'employee_id_field_id' => 1,
      'employee_name_field_id' => 2,
      'employee_email_field_id' => 3,
      'employee_phone_field_id' => 4,
      'employee_status_field_id' => 5,
      'employee_uid_field_id' => 6,
      'employee_office_field_id' => 7,
      'account_action_field_id' => 8,
      'target_system_field_id' => 9
    })

    # Mock custom fields exist for each ID
    CustomField.stubs(:find_by).with(id: 1, type: 'IssueCustomField').returns(CustomField.new(id: 1, name: 'Employee ID'))
    CustomField.stubs(:find_by).with(id: 2, type: 'IssueCustomField').returns(CustomField.new(id: 2, name: 'Employee Name'))
    CustomField.stubs(:find_by).with(id: 3, type: 'IssueCustomField').returns(CustomField.new(id: 3, name: 'Employee Email'))
    CustomField.stubs(:find_by).with(id: 4, type: 'IssueCustomField').returns(CustomField.new(id: 4, name: 'Employee Phone'))
    CustomField.stubs(:find_by).with(id: 5, type: 'IssueCustomField').returns(CustomField.new(id: 5, name: 'Employee Status'))
    CustomField.stubs(:find_by).with(id: 6, type: 'IssueCustomField').returns(CustomField.new(id: 6, name: 'Employee UID'))
    CustomField.stubs(:find_by).with(id: 7, type: 'IssueCustomField').returns(CustomField.new(id: 7, name: 'Employee Office'))
    CustomField.stubs(:find_by).with(id: 8, type: 'IssueCustomField').returns(CustomField.new(id: 8, name: 'Account Action'))
    CustomField.stubs(:find_by).with(id: 9, type: 'IssueCustomField').returns(CustomField.new(id: 9, name: 'Target System'))

    assert NysenateAuditUtils::CustomFieldConfiguration.valid?
  end

  def test_valid_with_incomplete_configuration
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'employee_name_field_id' => 2
    })

    refute NysenateAuditUtils::CustomFieldConfiguration.valid?
  end

  def test_autoconfigure_field_success
    # Mock custom field exists with expected name
    field = CustomField.new(id: 42, name: 'Employee ID')
    CustomField.stubs(:where).with(
      type: 'IssueCustomField',
      name: 'Employee ID'
    ).returns([field])

    # Mock Setting update
    Setting.expects(:plugin_nysenate_audit_utils=).with(
      @mock_settings.merge('employee_id_field_id' => 42)
    )

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_field('employee_id_field_id')
    assert result
  end

  def test_autoconfigure_field_not_found
    # Mock custom field doesn't exist
    CustomField.stubs(:where).returns([])

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_field('employee_id_field_id')
    refute result
  end

  def test_autoconfigure_all
    # Mock some fields exist
    employee_id_field = CustomField.new(id: 1, name: 'Employee ID')
    account_action_field = CustomField.new(id: 3, name: 'Account Action')

    # Stub where to return arrays that respond correctly to .first
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee ID').returns([employee_id_field])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee Name').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee Email').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee Phone').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee Status').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee UID').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Employee Office').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Account Action').returns([account_action_field])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Target System').returns([])

    Setting.stubs(:plugin_nysenate_audit_utils=)

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_all

    assert_includes result[:configured], 'employee_id_field_id'
    assert_includes result[:configured], 'account_action_field_id'
    assert_includes result[:failed], 'employee_name_field_id'
  end

  def test_field_status_configured
    CustomField.stubs(:find_by).with(id: 1, type: 'IssueCustomField').returns(
      CustomField.new(id: 1, name: 'Employee ID')
    )

    status = NysenateAuditUtils::CustomFieldConfiguration.field_status('employee_id_field_id')

    assert status[:configured]
    assert_equal 1, status[:field_id]
    assert_equal 'Employee ID', status[:field_name]
    assert_equal 'Employee ID', status[:expected_name]
    assert status[:required]
  end

  def test_field_status_not_configured
    Setting.stubs(:plugin_nysenate_audit_utils).returns({})

    status = NysenateAuditUtils::CustomFieldConfiguration.field_status('employee_id_field_id')

    refute status[:configured]
    assert_nil status[:field_id]
  end

  def test_configuration_status
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'employee_id_field_id' => 1,
      'employee_name_field_id' => 2,
      'account_action_field_id' => 3
      # target_system_field_id missing, and only 1 of 7 autofill fields configured
    })

    status = NysenateAuditUtils::CustomFieldConfiguration.configuration_status

    assert_equal 1, status[:reporting][:configured]
    assert_equal 1, status[:reporting][:total]
    assert status[:reporting][:complete]

    # employee_id is shared with reporting, so autofill should show 1 configured (employee_name)
    # Actually, employee_id is in reporting category, so autofill has employee_name, email, phone, status, uid, office = 6 total
    # Of those, only employee_name is configured = 1 configured
    assert_equal 1, status[:autofill][:configured]
    assert_equal 6, status[:autofill][:total]
    refute status[:autofill][:complete]

    assert_equal 1, status[:request_codes][:configured]
    assert_equal 2, status[:request_codes][:total]
    refute status[:request_codes][:complete]
  end

  def test_fields_by_category
    categories = NysenateAuditUtils::CustomFieldConfiguration.fields_by_category

    assert categories.key?(:reporting)
    assert categories.key?(:autofill)
    assert categories.key?(:request_codes)

    reporting_fields = categories[:reporting].map { |k, _v| k }
    assert_includes reporting_fields, 'employee_id_field_id'
  end
end
