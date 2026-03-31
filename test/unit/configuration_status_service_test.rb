# frozen_string_literal: true

require_relative '../test_helper'

class ConfigurationStatusServiceTest < ActiveSupport::TestCase
  def setup
    # Clear settings
    Setting.plugin_nysenate_audit_utils = {}
  end

  def teardown
    # Clean up
    Setting.plugin_nysenate_audit_utils = {}
  end

  # Test request_codes_status method
  test 'should return error when custom fields not configured' do
    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    assert_equal :error, status[:status]
    assert_equal false, status[:valid]
    assert_includes status[:errors].first, 'Custom fields for Account Action and Target System must be configured'
  end

  test 'should return error when mappings are missing for all values' do
    # Create custom fields
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete', 'Update']
    )

    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX']
    )

    # Configure fields but no mappings
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => target_system_field.id.to_s
    }

    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    assert_equal :error, status[:status]
    assert_equal false, status[:valid]
    assert_equal 2, status[:errors].size
    assert_includes status[:errors].join, 'Target System value'
    assert_includes status[:errors].join, 'Account Action value'
    assert_equal 2, status[:unmapped_systems].size
    assert_equal 3, status[:unmapped_actions].size
  end

  test 'should return ok when all mappings configured' do
    # Create custom fields
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX']
    )

    # Configure fields and mappings
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => target_system_field.id.to_s,
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR',
        'AIX' => 'AIX'
      },
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Delete' => 'I'
      }
    }

    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    assert_equal :ok, status[:status]
    assert_equal true, status[:valid]
    assert_empty status[:errors]
    assert_empty status[:warnings]
    assert_empty status[:unmapped_systems]
    assert_empty status[:unmapped_actions]
  end

  test 'should detect dangling system mappings' do
    # Create custom fields with limited values
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete']
    )

    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS']
    )

    # Configure with extra mapping for removed system
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => target_system_field.id.to_s,
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR',
        'Old System' => 'OLD'  # Dangling
      },
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Delete' => 'I'
      }
    }

    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    assert_equal :warning, status[:status]
    assert_equal true, status[:valid]
    assert_empty status[:errors]
    assert_equal 1, status[:warnings].size
    assert_includes status[:warnings].first, 'Target System mapping'
    assert_equal ['Old System'], status[:dangling_systems]
    assert_empty status[:dangling_actions]
  end

  test 'should detect dangling action mappings' do
    # Create custom fields
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add']
    )

    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS']
    )

    # Configure with extra mapping for removed action
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => target_system_field.id.to_s,
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR'
      },
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Old Action' => 'O'  # Dangling
      }
    }

    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    assert_equal :warning, status[:status]
    assert_equal true, status[:valid]
    assert_empty status[:errors]
    assert_equal 1, status[:warnings].size
    assert_includes status[:warnings].first, 'Account Action mapping'
    assert_empty status[:dangling_systems]
    assert_equal ['Old Action'], status[:dangling_actions]
  end

  test 'should handle combination of unmapped and dangling mappings' do
    # Create custom fields
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add', 'Delete', 'Update']
    )

    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS', 'AIX']
    )

    # Configure with partial mappings and some dangling
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => target_system_field.id.to_s,
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR',
        'Old System' => 'OLD'  # Dangling
      },
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Old Action' => 'O'  # Dangling
      }
    }

    status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status

    # Should show error for unmapped, but also warning for dangling
    assert_equal :error, status[:status]
    assert_equal false, status[:valid]
    assert_equal 2, status[:errors].size  # AIX unmapped, Delete & Update unmapped
    assert_equal 2, status[:warnings].size  # Old System and Old Action dangling
    assert_equal ['AIX'], status[:unmapped_systems]
    assert_equal ['Delete', 'Update'], status[:unmapped_actions]
    assert_equal ['Old System'], status[:dangling_systems]
    assert_equal ['Old Action'], status[:dangling_actions]
  end

  test 'overall_status should include request_codes section' do
    overall = NysenateAuditUtils::ConfigurationStatusService.overall_status

    assert overall[:sections].key?(:request_codes)
    assert overall[:sections][:request_codes].is_a?(Hash)
  end
end
