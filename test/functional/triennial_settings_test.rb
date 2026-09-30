# frozen_string_literal: true

require_relative '../test_helper'

class TriennialSettingsTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :users, :projects, :trackers, :projects_trackers, :issue_statuses

  def setup
    @request.session[:user_id] = 1
    @tracker = Tracker.find(1)
    @request_type = IssueCustomField.create!(
      name: 'Triennial Request Type', field_format: 'list',
      possible_values: ['New Process', 'Fix'], is_for_all: true, trackers: [@tracker]
    )
    IssueCustomField.create!(name: 'Triennial Notes', field_format: 'string',
                             is_for_all: true, trackers: [@tracker])
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'AIXA' },
        { 'project_id' => '1', 'tracker_id' => '2', 'mapping_mode' => 'account_request_code' },
        { 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'field',
          'field_id' => @request_type.id.to_s, 'value_codes' => { 'New Process' => 'NEW' } }
      ]
    }
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  def source_rows
    css_select('#triennial-sources-table tbody tr.triennial-source-row')
  end

  test 'renders the reordered columns' do
    get :plugin, params: { id: 'nysenate_audit_utils' }
    assert_response :success

    headers = css_select('#triennial-sources-table thead th').map { |th| th.text.strip }
    assert_equal ['Project', 'Tracker', 'Mapping Mode', 'Code(s)', ''], headers
  end

  test 'renders tracker and field names, not ids, as option labels' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows.first
    tracker_option = row.at_css('.ts-tracker-select option[selected]')
    assert_equal '1', tracker_option['value']
    assert_equal @tracker.name, tracker_option.text
  end

  test 'field picker only lists List fields' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    labels = source_rows.first.css('.ts-field-select option').map(&:text)
    assert_includes labels, 'Triennial Request Type'
    assert_not_includes labels, 'Triennial Notes'
  end

  test 'tracker mode shows a single code input' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows[0]
    assert_equal 'tracker', row.at_css('.ts-mode-select option[selected]')['value']
    assert_equal 'AIXA', row.at_css('input[name$="[code]"]')['value']
    assert_nil row.at_css('.ts-panel[data-mode="tracker"]')['hidden']
    assert row.at_css('.ts-panel[data-mode="field"]')['hidden']
    assert_includes row.at_css('.ts-field-select')['class'], 'ts-hidden'
  end

  def enable_account_request_fields(trackers)
    action = IssueCustomField.create!(name: 'Triennial Action', field_format: 'list',
                                      possible_values: %w[Add], is_for_all: true, trackers: trackers)
    system = IssueCustomField.create!(name: 'Triennial System', field_format: 'list',
                                      possible_values: %w[AIX], is_for_all: true, trackers: trackers)
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'account_action_field_id' => action.id.to_s, 'target_system_field_id' => system.id.to_s
    )
  end

  def arc_option(row)
    row.at_css('.ts-mode-select option[value="account_request_code"]')
  end

  test 'account request code mode points at the Account Request Code Configuration section' do
    enable_account_request_fields([Tracker.find(2)])
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows[1]
    assert_nil arc_option(row)['disabled']
    assert_nil row.at_css('.ts-arc-note')['hidden']
    assert row.at_css('.ts-arc-unavailable-warning')['hidden']
    assert_includes row.at_css('.ts-arc-note').text, 'Account Request Code Configuration'
  end

  test 'account request code is disabled where the fields are not enabled' do
    enable_account_request_fields([Tracker.find(2)])
    get :plugin, params: { id: 'nysenate_audit_utils' }

    option = arc_option(source_rows[0]) # project 1 / tracker 1: fields not on tracker 1
    assert option['disabled']
    assert_includes option.text, 'fields not enabled'
  end

  test 'a saved account request code row without the fields keeps its mode and shows a warning' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows[1] # saved as account_request_code, fields not configured
    option = arc_option(row)
    assert option['selected']
    assert_nil option['disabled'], 'stays selectable so a save keeps the value'
    assert_nil row.at_css('.ts-arc-unavailable-warning')['hidden']
    assert row.at_css('.ts-arc-note')['hidden']
    assert_select '.config-needed-notice li', text: /uses Account Request Code, but the Account Action and Target System fields are not enabled/
  end

  test 'new-row template starts with account request code disabled' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    template = Nokogiri::HTML.fragment(css_select('#triennial-source-row-template').first.inner_html)
    assert template.at_css('.ts-mode-select option[value="account_request_code"]')['disabled']
  end

  test 'field picker excludes List fields not enabled on the project' do
    IssueCustomField.create!(name: 'Other Project List', field_format: 'list', possible_values: %w[A],
                             is_for_all: false, projects: [Project.find(2)], trackers: [@tracker])
    get :plugin, params: { id: 'nysenate_audit_utils' }

    assert_not_includes source_rows[0].css('.ts-field-select option').map(&:text), 'Other Project List'
    assert_includes source_rows[2].css('.ts-field-select option').map(&:text), 'Other Project List'
  end

  test 'field mode renders a code input per field value' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows[2]
    assert_not_includes row.at_css('.ts-field-select')['class'], 'ts-hidden'
    assert row.at_css('.ts-no-field-warning')['hidden'], 'warning hidden once a field is selected'

    inputs = row.css('.ts-value-codes input')
    assert_equal ['New Process', 'Fix'], row.css('.ts-value-label').map(&:text)
    assert_equal 'NEW', inputs[0]['value']
    assert_match(/\[value_codes\]\[New Process\]\z/, inputs[0]['name'])
  end

  test 'field mode without a field shows the warning' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'field', 'field_id' => '' }
      ]
    }
    get :plugin, params: { id: 'nysenate_audit_utils' }

    row = source_rows.first
    assert_nil row.at_css('.ts-no-field-warning')['hidden']
    assert_empty row.css('.ts-value-codes input')
  end

  test 'saving the form round-trips through the config module' do
    post :plugin, params: {
      id: 'nysenate_audit_utils',
      settings: {
        'triennial_audit_sources' => {
          'new_0' => { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'field',
                       'field_id' => @request_type.id.to_s,
                       'value_codes' => { 'New Process' => 'NEW', 'Fix' => 'FIX' } }
        }
      }
    }

    issue = Issue.create!(project_id: 1, tracker: @tracker, author_id: 1, status_id: 1,
                          subject: 'Round trip', custom_field_values: { @request_type.id => 'Fix' })
    assert_equal 'FIX', NysenateAuditUtils::TriennialAuditConfiguration.resolve_code(issue)
  end

  test 'renames the request code accordion' do
    get :plugin, params: { id: 'nysenate_audit_utils' }

    header = css_select('.accordion-header[data-section="request-codes"] h3').first.text
    assert_includes header, 'Account Request Code Configuration'
  end
  test 'warns on source rows whose project/tracker lacks Selected for Audit' do
    field = IssueCustomField.create!(name: 'Triennial Selected', field_format: 'list', possible_values: %w[No 2025],
                                     is_for_all: true, trackers: [@tracker])
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'selected_for_audit_field_id' => field.id.to_s
    )

    get :plugin, params: { id: 'nysenate_audit_utils' }

    warnings = source_rows.map { |row| row.at_css('.ts-sfa-warning') }
    assert warnings[0]['hidden'], 'project 1 / tracker 1 has the field'
    assert_nil warnings[1]['hidden'], 'project 1 / tracker 2 lacks the field'
    assert_match(/Triennial Selected field is not enabled/, warnings[1].text)
    assert_select '#triennial-source-row-template'
    assert_match(/does not have the Triennial Selected field enabled/, response.body)
  end
end
