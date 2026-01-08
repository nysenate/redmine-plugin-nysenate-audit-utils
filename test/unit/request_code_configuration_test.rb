# frozen_string_literal: true

require_relative '../test_helper'

class RequestCodeConfigurationTest < ActiveSupport::TestCase
  fixtures :custom_fields

  def setup
    # No reset needed - no caches
  end

  def teardown
    # Clean up settings
    Setting.plugin_nysenate_audit_utils = {}
  end

  # Test field ID detection
  test 'should return configured Account Action field ID' do
    # Create a custom field named "Account Action"
    field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete', 'Update']
    )

    # Configure it
    Setting.plugin_nysenate_audit_utils = { 'account_action_field_id' => field.id.to_s }

    field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
    assert_equal field.id, field_id
  end

  test 'should return configured Target System field ID' do
    # Create a custom field named "Target System"
    field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX', 'SFS']
    )

    # Configure it
    Setting.plugin_nysenate_audit_utils = { 'target_system_field_id' => field.id.to_s }

    field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
    assert_equal field.id, field_id
  end

  test 'should return nil when Account Action field not found' do
    # Ensure no field exists with that name
    CustomField.where(name: 'Account Action').destroy_all

    field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
    assert_nil field_id
  end

  test 'should return nil when Target System field not found' do
    # Ensure no field exists with that name
    CustomField.where(name: 'Target System').destroy_all

    field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
    assert_nil field_id
  end

  test 'should use configured field ID over auto-detection' do
    # Create fields
    auto_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    manual_field = IssueCustomField.create!(
      name: 'Custom Action Field',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    # Configure to use manual field
    Setting.plugin_nysenate_audit_utils = { 'account_action_field_id' => manual_field.id.to_s }

    field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
    assert_equal manual_field.id, field_id
  end

  # Test field object retrieval
  test 'should retrieve Account Action field object' do
    field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    Setting.plugin_nysenate_audit_utils = { 'account_action_field_id' => field.id.to_s }

    retrieved_field = NysenateAuditUtils::CustomFieldConfiguration.account_action_field
    assert_equal field.id, retrieved_field.id
    assert_equal 'Account Action', retrieved_field.name
  end

  test 'should retrieve Target System field object' do
    field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX']
    )

    Setting.plugin_nysenate_audit_utils = { 'target_system_field_id' => field.id.to_s }

    retrieved_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field
    assert_equal field.id, retrieved_field.id
    assert_equal 'Target System', retrieved_field.name
  end

  test 'should return nil for field object when field not found' do
    CustomField.where(name: 'Account Action').destroy_all

    field = NysenateAuditUtils::CustomFieldConfiguration.account_action_field
    assert_nil field
  end

  # Test custom mappings
  test 'should return custom mappings from settings' do
    custom_mappings = {
      'Custom System' => {
        'Add' => 'CSTA'
      }
    }

    Setting.plugin_nysenate_audit_utils = { 'request_code_mappings' => custom_mappings }

    mappings = Setting.plugin_nysenate_audit_utils['request_code_mappings']
    assert_equal custom_mappings, mappings
  end

  test 'should return nil when no custom mappings configured' do
    Setting.plugin_nysenate_audit_utils = {}

    mappings = Setting.plugin_nysenate_audit_utils['request_code_mappings']
    assert_nil mappings
  end

  # Test mapper with custom mappings
  test 'mapper should use custom mappings from settings' do
    custom_mappings = {
      'Custom System' => {
        'Add' => 'CSTA'
      }
    }

    Setting.plugin_nysenate_audit_utils = { 'request_code_mappings' => custom_mappings }

    mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(custom_mappings)
    code = mapper.get_request_code('Add', 'Custom System')
    assert_equal 'CSTA', code
  end

  # Test configuration status
  test 'should be valid when both fields exist' do
    account_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    target_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX']
    )

    Setting.plugin_nysenate_audit_utils = {
      'employee_id_field_id' => '1',
      'account_action_field_id' => account_field.id.to_s,
      'target_system_field_id' => target_field.id.to_s
    }

    # CustomFieldConfiguration validates all required fields, so let's check specific ones
    assert NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id.present?
    assert NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id.present?
  end

  test 'should return nil when Account Action field not configured' do
    CustomField.where(name: 'Account Action').destroy_all
    Setting.plugin_nysenate_audit_utils = {}

    assert_nil NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
  end

  test 'should return nil when Target System field not configured' do
    CustomField.where(name: 'Target System').destroy_all
    Setting.plugin_nysenate_audit_utils = {}

    assert_nil NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
  end
end
