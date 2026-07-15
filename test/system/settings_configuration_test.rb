# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end (browser) tests for the Audit Utils *admin plugin settings* page
# (Administration -> Plugins -> Configure), which renders at
# /settings/plugin/nysenate_audit_utils via the `settings/audit_utils_settings`
# partial.
#
# Covers the three interactive, JS/AJAX-driven controls on that page:
#   1. "Auto-Configure All Fields" -- POST link that maps every custom field by
#      name, flipping each row's status indicator to a green check.
#   2. "Test Connection" -- a plain <button> whose JS `fetch` POSTs to
#      test_ess_connection and renders success/failure into a result span.
#   3. Dangling request-code mapping cleanup -- DELETE links that remove
#      mappings whose key no longer exists as a custom-field value.
#
# ESS is stubbed in-process by WebMock (see AuditUtilsSystemTestCase). All
# custom-field names/values created here are synthetic.
class SettingsConfigurationTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  SETTINGS_PATH = '/settings/plugin/nysenate_audit_utils'

  setup do
    @tracker = Tracker.find(1)
    log_in_as_admin
  end

  # ==========================================================================
  # 1. Auto-Configure All Fields
  # ==========================================================================

  def test_auto_configure_all_fields_flips_status_indicators_to_configured
    # Every field the plugin knows about exists by name, but NONE is mapped in
    # settings yet (core's setup cleared all Settings), so every row starts
    # "Not configured".
    create_all_audit_custom_fields

    visit SETTINGS_PATH
    open_all_config_sections

    # Pre-state: representative rows are unconfigured.
    assert_field_row_status 'Account Holder Type', configured: false
    assert_field_row_status 'Account Action', configured: false
    assert_field_row_status 'Target System', configured: false

    # Click the POST link; it carries a data-confirm dialog.
    accept_confirm { click_link 'Auto-Configure All Fields' }

    # After the redirect, a success flash confirms the mapping ran.
    assert_text 'Successfully autoconfigured'

    # Status indicators now show a green check with the detected field name.
    open_all_config_sections
    assert_field_row_status 'Account Holder Type', configured: true
    assert_field_row_status 'Account Action', configured: true
    assert_field_row_status 'Target System', configured: true
  end

  # ==========================================================================
  # 2. Test ESS Connection
  # ==========================================================================

  def test_test_ess_connection_reports_success
    configure_ess!
    stub_ess_connection_success

    visit SETTINGS_PATH
    open_all_config_sections

    click_button 'Test Connection'

    within '#test-ess-connection-result' do
      assert_text '✓'
      assert_text 'connection successful'
    end
  end

  def test_test_ess_connection_reports_failure
    configure_ess!
    stub_ess_connection_failure(status: 500)

    visit SETTINGS_PATH
    open_all_config_sections

    click_button 'Test Connection'

    within '#test-ess-connection-result' do
      # The JS prefixes any non-success response with a red cross.
      assert_text '✗'
    end
  end

  # ==========================================================================
  # 3. Dangling request-code mapping cleanup
  # ==========================================================================

  def test_delete_single_dangling_system_mapping
    setup_standard_bachelp_fields(@tracker)
    # 'Legacy System' is NOT a Target System custom-field value -> dangling.
    add_dangling_system_mapping('Legacy System' => 'LEG')

    visit SETTINGS_PATH
    open_all_config_sections

    # The dangling row is rendered with its (struck-through) value.
    assert_selector 'tr.dangling-mapping', text: 'Legacy System'

    row = find('tr.dangling-mapping', text: 'Legacy System')
    accept_confirm { within(row) { click_link 'Delete' } }

    assert_text "Deleted dangling Target System mapping for 'Legacy System'"

    # The dangling block is gone entirely (no dangling keys remain).
    open_all_config_sections
    assert_no_selector 'tr.dangling-mapping'

    # And it is really removed from persisted settings.
    prefixes = Setting.plugin_nysenate_audit_utils['request_code_system_prefixes']
    assert_not prefixes.key?('Legacy System')
  end

  def test_delete_all_dangling_system_mappings
    setup_standard_bachelp_fields(@tracker)
    add_dangling_system_mapping('Legacy System' => 'LEG', 'Retired System' => 'RET')

    visit SETTINGS_PATH
    open_all_config_sections

    assert_selector 'tr.dangling-mapping', text: 'Legacy System'
    assert_selector 'tr.dangling-mapping', text: 'Retired System'

    accept_confirm { click_link 'Delete All Dangling System Mappings' }

    assert_text 'Deleted 2 dangling Target System mapping'

    open_all_config_sections
    assert_no_selector 'tr.dangling-mapping'

    prefixes = Setting.plugin_nysenate_audit_utils['request_code_system_prefixes']
    assert_not prefixes.key?('Legacy System')
    assert_not prefixes.key?('Retired System')
  end

  private

  # --------------------------------------------------------------------------
  # Local helpers (kept here; the shared base helper is read-only)
  # --------------------------------------------------------------------------

  # Create an IssueCustomField for every field the plugin maps, matched by the
  # exact name auto-configure looks for. Does NOT write them into settings.
  def create_all_audit_custom_fields
    NysenateAuditUtils::CustomFieldConfiguration::FIELD_DEFINITIONS.each_value do |definition|
      create_or_find_field(definition[:name])
    end
  end

  # The accordions default to collapsed; reveal every section so its controls
  # and status indicators are visible to Capybara (which ignores hidden text).
  def open_all_config_sections
    click_button 'Expand All'
  end

  # Assert the custom-field-config row for `field_name` shows the expected
  # status: a green check + name when configured, or the "Not configured"
  # warning otherwise.
  def assert_field_row_status(field_name, configured:)
    row = find('table.audit-fields-config tbody tr', text: /\A#{Regexp.escape(field_name)}/)
    within(row) do
      if configured
        assert_selector 'span.status-configured', text: "✓ #{field_name}"
      else
        assert_selector 'span.status-missing', text: 'Not configured'
      end
    end
  end

  # Merge extra Target System prefix mappings into the saved settings without
  # disturbing the rest (setup_standard_bachelp_fields already populated them).
  def add_dangling_system_mapping(extra)
    settings = Setting.plugin_nysenate_audit_utils
    prefixes = (settings['request_code_system_prefixes'] || {}).merge(extra)
    Setting.plugin_nysenate_audit_utils =
      settings.merge('request_code_system_prefixes' => prefixes)
  end
end
