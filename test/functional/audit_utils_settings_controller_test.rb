# frozen_string_literal: true

require_relative '../test_helper'

class AuditUtilsSettingsControllerTest < ActionController::TestCase
  fixtures :users, :roles

  def setup
    @admin = User.find(1)
    @request.session[:user_id] = @admin.id
    Setting.plugin_nysenate_audit_utils = {}
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  # Test delete_dangling_mapping
  test 'should delete single dangling system mapping' do
    # Set up mappings with dangling entry
    Setting.plugin_nysenate_audit_utils = {
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR',
        'Old System' => 'OLD'
      }
    }

    delete :delete_dangling_mapping, params: { type: 'system', value: 'Old System' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_equal "Deleted dangling Target System mapping for 'Old System'", flash[:notice]

    # Verify it was deleted
    settings = Setting.plugin_nysenate_audit_utils
    assert_equal({ 'Oracle / SFMS' => 'USR' }, settings['request_code_system_prefixes'])
  end

  test 'should delete single dangling action mapping' do
    # Set up mappings with dangling entry
    Setting.plugin_nysenate_audit_utils = {
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Old Action' => 'O'
      }
    }

    delete :delete_dangling_mapping, params: { type: 'action', value: 'Old Action' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_equal "Deleted dangling Account Action mapping for 'Old Action'", flash[:notice]

    # Verify it was deleted
    settings = Setting.plugin_nysenate_audit_utils
    assert_equal({ 'Add' => 'A' }, settings['request_code_action_suffixes'])
  end

  test 'should return error for invalid mapping type' do
    delete :delete_dangling_mapping, params: { type: 'invalid', value: 'test' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Invalid mapping type/, flash[:error]
  end

  test 'should return error for missing parameters' do
    delete :delete_dangling_mapping, params: { type: 'system' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Invalid parameters/, flash[:error]
  end

  test 'should handle missing mapping gracefully' do
    Setting.plugin_nysenate_audit_utils = {
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR'
      }
    }

    delete :delete_dangling_mapping, params: { type: 'system', value: 'Nonexistent' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Mapping not found/, flash[:warning]
  end

  # Test delete_all_dangling_mappings
  test 'should delete all dangling system mappings' do
    # Create custom fields
    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS']
    )

    # Set up mappings with multiple dangling entries
    Setting.plugin_nysenate_audit_utils = {
      'target_system_field_id' => target_system_field.id.to_s,
      'account_action_field_id' => '1',
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR',
        'Old System 1' => 'OLD1',
        'Old System 2' => 'OLD2'
      }
    }

    delete :delete_all_dangling_mappings, params: { type: 'system' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Deleted 2 dangling Target System mapping/, flash[:notice]

    # Verify only valid mapping remains
    settings = Setting.plugin_nysenate_audit_utils
    assert_equal({ 'Oracle / SFMS' => 'USR' }, settings['request_code_system_prefixes'])
  end

  test 'should delete all dangling action mappings' do
    # Create custom fields
    account_action_field = IssueCustomField.create!(
      name: 'Account Action',
      field_format: 'list',
      possible_values: ['Add']
    )

    # Set up mappings with multiple dangling entries
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => account_action_field.id.to_s,
      'target_system_field_id' => '1',
      'request_code_action_suffixes' => {
        'Add' => 'A',
        'Old Action 1' => 'O1',
        'Old Action 2' => 'O2'
      }
    }

    delete :delete_all_dangling_mappings, params: { type: 'action' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Deleted 2 dangling Account Action mapping/, flash[:notice]

    # Verify only valid mapping remains
    settings = Setting.plugin_nysenate_audit_utils
    assert_equal({ 'Add' => 'A' }, settings['request_code_action_suffixes'])
  end

  test 'should handle no dangling mappings' do
    # Create custom fields
    target_system_field = IssueCustomField.create!(
      name: 'Target System',
      field_format: 'list',
      possible_values: ['Oracle / SFMS']
    )

    # Set up mappings with no dangling entries
    Setting.plugin_nysenate_audit_utils = {
      'target_system_field_id' => target_system_field.id.to_s,
      'account_action_field_id' => '1',
      'request_code_system_prefixes' => {
        'Oracle / SFMS' => 'USR'
      }
    }

    delete :delete_all_dangling_mappings, params: { type: 'system' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /No dangling mappings found/, flash[:warning]
  end

  test 'should return error for invalid type in delete_all' do
    delete :delete_all_dangling_mappings, params: { type: 'invalid' }

    assert_redirected_to plugin_settings_path('nysenate_audit_utils')
    assert_match /Invalid mapping type/, flash[:error]
  end

  test 'should require admin for delete_dangling_mapping' do
    # Log in as non-admin user
    user = User.find(2)
    @request.session[:user_id] = user.id

    delete :delete_dangling_mapping, params: { type: 'system', value: 'test' }

    assert_response 403
  end

  test 'should require admin for delete_all_dangling_mappings' do
    # Log in as non-admin user
    user = User.find(2)
    @request.session[:user_id] = user.id

    delete :delete_all_dangling_mappings, params: { type: 'system' }

    assert_response 403
  end
end
