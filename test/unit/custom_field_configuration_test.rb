# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class CustomFieldConfigurationTest < ActiveSupport::TestCase
  def setup
    # Mock plugin settings - use string keys as Redmine does
    @mock_settings = {
      'user_type_field_id' => 1,
      'user_id_field_id' => 2,
      'user_name_field_id' => 3,
      'account_action_field_id' => 4,
      'target_system_field_id' => 5
    }

    Setting.stubs(:plugin_nysenate_audit_utils).returns(@mock_settings)
  end

  def test_get_field_id_with_configured_field
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_id_field_id')
    assert_equal 2, field_id
  end

  def test_get_field_id_with_unconfigured_field
    field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_location_field_id')
    assert_nil field_id
  end

  def test_all_field_ids
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.all_field_ids

    assert_equal 1, field_ids['user_type_field_id']
    assert_equal 2, field_ids['user_id_field_id']
    assert_equal 3, field_ids['user_name_field_id']
    assert_equal 4, field_ids['account_action_field_id']
    assert_equal 5, field_ids['target_system_field_id']
    assert_nil field_ids['user_location_field_id']
  end

  def test_user_type_field_id
    assert_equal 1, NysenateAuditUtils::CustomFieldConfiguration.user_type_field_id
  end

  def test_user_id_field_id
    assert_equal 2, NysenateAuditUtils::CustomFieldConfiguration.user_id_field_id
  end

  def test_account_action_field_id
    assert_equal 4, NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
  end

  def test_target_system_field_id
    assert_equal 5, NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
  end

  def test_autofill_field_ids
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

    assert_equal 1, field_ids[:user_type]
    assert_equal 2, field_ids[:user_id]
    assert_equal 3, field_ids[:user_name]
    assert_nil field_ids[:user_email] # Not configured
  end

  def test_validate_with_all_required_fields
    # Mock all required fields as configured (all 10 fields)
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'user_type_field_id' => 1,
      'user_id_field_id' => 2,
      'user_name_field_id' => 3,
      'user_email_field_id' => 4,
      'user_phone_field_id' => 5,
      'user_status_field_id' => 6,
      'user_uid_field_id' => 7,
      'user_location_field_id' => 8,
      'account_action_field_id' => 9,
      'target_system_field_id' => 10
    })

    # Mock custom fields exist for each ID
    CustomField.stubs(:find_by).with(id: 1, type: 'IssueCustomField').returns(CustomField.new(id: 1, name: 'User Type'))
    CustomField.stubs(:find_by).with(id: 2, type: 'IssueCustomField').returns(CustomField.new(id: 2, name: 'User ID'))
    CustomField.stubs(:find_by).with(id: 3, type: 'IssueCustomField').returns(CustomField.new(id: 3, name: 'User Name'))
    CustomField.stubs(:find_by).with(id: 4, type: 'IssueCustomField').returns(CustomField.new(id: 4, name: 'User Email'))
    CustomField.stubs(:find_by).with(id: 5, type: 'IssueCustomField').returns(CustomField.new(id: 5, name: 'User Phone'))
    CustomField.stubs(:find_by).with(id: 6, type: 'IssueCustomField').returns(CustomField.new(id: 6, name: 'User Status'))
    CustomField.stubs(:find_by).with(id: 7, type: 'IssueCustomField').returns(CustomField.new(id: 7, name: 'User UID'))
    CustomField.stubs(:find_by).with(id: 8, type: 'IssueCustomField').returns(CustomField.new(id: 8, name: 'User Location'))
    CustomField.stubs(:find_by).with(id: 9, type: 'IssueCustomField').returns(CustomField.new(id: 9, name: 'Account Action'))
    CustomField.stubs(:find_by).with(id: 10, type: 'IssueCustomField').returns(CustomField.new(id: 10, name: 'Target System'))

    errors = NysenateAuditUtils::CustomFieldConfiguration.validate
    assert_empty errors
  end

  def test_validate_with_missing_required_field
    # Mock missing user_id field
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'account_action_field_id' => 2,
      'target_system_field_id' => 3
    })

    errors = NysenateAuditUtils::CustomFieldConfiguration.validate
    assert_includes errors, "Required field 'User ID' (user_id_field_id) is not configured"
  end

  def test_valid_with_complete_configuration
    # Mock all required fields as configured (all 10 fields)
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'user_type_field_id' => 1,
      'user_id_field_id' => 2,
      'user_name_field_id' => 3,
      'user_email_field_id' => 4,
      'user_phone_field_id' => 5,
      'user_status_field_id' => 6,
      'user_uid_field_id' => 7,
      'user_location_field_id' => 8,
      'account_action_field_id' => 9,
      'target_system_field_id' => 10
    })

    # Mock custom fields exist for each ID
    CustomField.stubs(:find_by).with(id: 1, type: 'IssueCustomField').returns(CustomField.new(id: 1, name: 'User Type'))
    CustomField.stubs(:find_by).with(id: 2, type: 'IssueCustomField').returns(CustomField.new(id: 2, name: 'User ID'))
    CustomField.stubs(:find_by).with(id: 3, type: 'IssueCustomField').returns(CustomField.new(id: 3, name: 'User Name'))
    CustomField.stubs(:find_by).with(id: 4, type: 'IssueCustomField').returns(CustomField.new(id: 4, name: 'User Email'))
    CustomField.stubs(:find_by).with(id: 5, type: 'IssueCustomField').returns(CustomField.new(id: 5, name: 'User Phone'))
    CustomField.stubs(:find_by).with(id: 6, type: 'IssueCustomField').returns(CustomField.new(id: 6, name: 'User Status'))
    CustomField.stubs(:find_by).with(id: 7, type: 'IssueCustomField').returns(CustomField.new(id: 7, name: 'User UID'))
    CustomField.stubs(:find_by).with(id: 8, type: 'IssueCustomField').returns(CustomField.new(id: 8, name: 'User Location'))
    CustomField.stubs(:find_by).with(id: 9, type: 'IssueCustomField').returns(CustomField.new(id: 9, name: 'Account Action'))
    CustomField.stubs(:find_by).with(id: 10, type: 'IssueCustomField').returns(CustomField.new(id: 10, name: 'Target System'))

    assert NysenateAuditUtils::CustomFieldConfiguration.valid?
  end

  def test_valid_with_incomplete_configuration
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'user_name_field_id' => 2
    })

    refute NysenateAuditUtils::CustomFieldConfiguration.valid?
  end

  def test_autoconfigure_field_success
    # Mock custom field exists with expected name
    field = CustomField.new(id: 42, name: 'User ID')
    CustomField.stubs(:where).with(
      type: 'IssueCustomField',
      name: 'User ID'
    ).returns([field])

    # Mock Setting update
    Setting.expects(:plugin_nysenate_audit_utils=).with(
      @mock_settings.merge('user_id_field_id' => 42)
    )

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_field('user_id_field_id')
    assert result
  end

  def test_autoconfigure_field_not_found
    # Mock custom field doesn't exist
    CustomField.stubs(:where).returns([])

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_field('user_id_field_id')
    refute result
  end

  def test_autoconfigure_all
    # Mock some fields exist
    user_type_field = CustomField.new(id: 1, name: 'User Type')
    user_id_field = CustomField.new(id: 2, name: 'User ID')
    account_action_field = CustomField.new(id: 3, name: 'Account Action')

    # Stub where to return arrays that respond correctly to .first
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Type').returns([user_type_field])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User ID').returns([user_id_field])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Name').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Email').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Phone').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Status').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User UID').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'User Location').returns([])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Account Action').returns([account_action_field])
    CustomField.stubs(:where).with(type: 'IssueCustomField', name: 'Target System').returns([])

    Setting.stubs(:plugin_nysenate_audit_utils=)

    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_all

    assert_includes result[:configured], 'user_type_field_id'
    assert_includes result[:configured], 'user_id_field_id'
    assert_includes result[:configured], 'account_action_field_id'
    assert_includes result[:failed], 'user_name_field_id'
  end

  def test_field_status_configured
    CustomField.stubs(:find_by).with(id: 2, type: 'IssueCustomField').returns(
      CustomField.new(id: 2, name: 'User ID')
    )

    status = NysenateAuditUtils::CustomFieldConfiguration.field_status('user_id_field_id')

    assert status[:configured]
    assert_equal 2, status[:field_id]
    assert_equal 'User ID', status[:field_name]
    assert_equal 'User ID', status[:expected_name]
    assert status[:required]
  end

  def test_field_status_not_configured
    Setting.stubs(:plugin_nysenate_audit_utils).returns({})

    status = NysenateAuditUtils::CustomFieldConfiguration.field_status('user_id_field_id')

    refute status[:configured]
    assert_nil status[:field_id]
  end

  def test_configuration_status
    Setting.stubs(:plugin_nysenate_audit_utils).returns({
      'user_type_field_id' => 1,
      'user_id_field_id' => 2,
      'user_name_field_id' => 3,
      'account_action_field_id' => 4
      # target_system_field_id missing, and only 3 of 8 autofill fields configured
    })

    status = NysenateAuditUtils::CustomFieldConfiguration.configuration_status

    assert_equal 1, status[:reporting][:configured]
    assert_equal 1, status[:reporting][:total]
    assert status[:reporting][:complete]

    # user_id is in reporting category, so autofill has user_type, user_name, email, phone, status, uid, office = 7 total
    # Of those, user_type and user_name are configured = 2 configured
    assert_equal 2, status[:autofill][:configured]
    assert_equal 7, status[:autofill][:total]
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
    assert_includes reporting_fields, 'user_id_field_id'

    autofill_fields = categories[:autofill].map { |k, _v| k }
    assert_includes autofill_fields, 'user_type_field_id'
  end
end
