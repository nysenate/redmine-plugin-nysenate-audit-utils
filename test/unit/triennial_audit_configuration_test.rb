# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class TriennialAuditConfigurationTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses, :users, :enumerations

  Config = NysenateAuditUtils::TriennialAuditConfiguration

  def setup
    @project = Project.find(1)
    @tracker = Tracker.find(1)
    @request_type = IssueCustomField.create!(
      name: 'Triennial Request Type', field_format: 'list',
      possible_values: ['New Process', 'Enhance Existing Process', 'Fix'],
      is_for_all: true, trackers: [@tracker]
    )
    Setting.plugin_nysenate_audit_utils = {}
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  def create_issue(custom_values = {})
    Issue.create!(project: @project, tracker: @tracker, author_id: 1, status_id: 1,
                  subject: 'Triennial test', custom_field_values: custom_values)
  end

  def configure(*rows)
    Setting.plugin_nysenate_audit_utils = { 'triennial_audit_sources' => rows }
  end

  test 'sources normalizes the index-keyed hash the settings form saves' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => {
        'existing_0' => { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker' },
        'new_0' => { 'project_id' => '2', 'tracker_id' => '2', 'mapping_mode' => 'tracker' }
      }
    }

    assert_equal 2, Config.sources.size
    assert_equal [[1, 1], [2, 2]], Config.source_pairs
  end

  test 'sources is empty when unset' do
    assert_equal [], Config.sources
    assert_equal [], Config.source_pairs
  end

  test 'source_pairs skips rows missing a project or tracker' do
    configure({ 'project_id' => '1', 'tracker_id' => '' }, { 'project_id' => '1', 'tracker_id' => '1' })

    assert_equal [[1, 1]], Config.source_pairs
  end

  test 'tracker mode resolves every ticket to the one code' do
    configure({ 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'AIXA' })

    assert_equal 'AIXA', Config.resolve_code(create_issue)
  end

  test 'field mode resolves the code mapped to the ticket field value' do
    configure(
      'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'field',
      'field_id' => @request_type.id.to_s,
      'value_codes' => { 'New Process' => 'NEW', 'Enhance Existing Process' => 'ENH', 'Fix' => '' }
    )

    assert_equal 'NEW', Config.resolve_code(create_issue(@request_type.id => 'New Process'))
    assert_equal 'ENH', Config.resolve_code(create_issue(@request_type.id => 'Enhance Existing Process'))
    assert_nil Config.resolve_code(create_issue(@request_type.id => 'Fix')), 'blank mapped code is unresolved'
    assert_nil Config.resolve_code(create_issue), 'blank field value is unresolved'
  end

  test 'field mode with no field selected is unresolved' do
    configure({ 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'field', 'field_id' => '' })

    assert_nil Config.resolve_code(create_issue(@request_type.id => 'New Process'))
  end

  test 'account request code mode resolves via the request code mapper' do
    action = IssueCustomField.create!(name: 'Triennial Action', field_format: 'list',
                                      possible_values: %w[Add Delete], is_for_all: true, trackers: [@tracker])
    system = IssueCustomField.create!(name: 'Triennial System', field_format: 'list',
                                      possible_values: %w[AIX], is_for_all: true, trackers: [@tracker])
    Setting.plugin_nysenate_audit_utils = {
      'account_action_field_id' => action.id.to_s,
      'target_system_field_id' => system.id.to_s,
      'request_code_system_prefixes' => { 'AIX' => 'AIX' },
      'request_code_action_suffixes' => { 'Add' => 'A' },
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'account_request_code' }
      ]
    }

    assert_equal 'AIXA', Config.resolve_code(create_issue(action.id => 'Add', system.id => 'AIX'))
    assert_nil Config.resolve_code(create_issue(action.id => 'Delete', system.id => 'AIX'))
  end

  test 'a ticket outside every configured source is unresolved' do
    configure({ 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'X' })

    assert_nil Config.resolve_code(create_issue)
  end

  def configure_account_request_fields(trackers: [@tracker], projects: nil)
    field_opts = projects ? { is_for_all: false, projects: projects } : { is_for_all: true }
    action = IssueCustomField.create!(name: 'Triennial Action', field_format: 'list',
                                      possible_values: %w[Add], trackers: trackers, **field_opts)
    system = IssueCustomField.create!(name: 'Triennial System', field_format: 'list',
                                      possible_values: %w[AIX], trackers: trackers, **field_opts)
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'account_action_field_id' => action.id.to_s, 'target_system_field_id' => system.id.to_s
    )
  end

  test 'account request code is available only where both fields are enabled' do
    configure_account_request_fields(projects: [@project])

    assert Config.account_request_code_available?(@project, @tracker)
    assert_not Config.account_request_code_available?(Project.find(2), @tracker), 'field not enabled on project'
    assert_not Config.account_request_code_available?(@project, Tracker.find(2)), 'field not enabled on tracker'
  end

  test 'account request code is unavailable when the fields are not configured' do
    assert_not Config.account_request_code_available?(@project, @tracker)
  end

  test 'available list fields are scoped to the project as well as the tracker' do
    project_only = IssueCustomField.create!(name: 'Project-scoped List', field_format: 'list',
                                            possible_values: %w[A], is_for_all: false,
                                            projects: [Project.find(2)], trackers: [@tracker])
    IssueCustomField.create!(name: 'Triennial Text', field_format: 'string', is_for_all: true, trackers: [@tracker])

    names = Config.available_list_fields(@project, @tracker).map(&:name)
    assert_includes names, 'Triennial Request Type'
    assert_not_includes names, project_only.name
    assert_not_includes names, 'Triennial Text'
  end

  test 'unavailable_account_request_code_sources lists rows missing the fields' do
    configure_account_request_fields(projects: [@project])
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'account_request_code' },
        { 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'account_request_code' },
        { 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'X' }
      ]
    )

    assert_equal ['2'], Config.unavailable_account_request_code_sources.pluck('project_id')
  end

  test 'autoconfigure adds one account request code row for the Account Request tracker' do
    tracker = Tracker.create!(name: 'Account Request', default_status_id: 1)
    @project.trackers << tracker
    configure_account_request_fields(trackers: [tracker])

    assert Config.autoconfigure_account_request!
    assert_equal [{ 'project_id' => @project.id, 'tracker_id' => tracker.id,
                    'mapping_mode' => 'account_request_code' }], Config.sources

    assert_not Config.autoconfigure_account_request!, 'does not add a duplicate row'
    assert_equal 1, Config.sources.size
  end

  test 'autoconfigure skips projects without the account request fields enabled' do
    tracker = Tracker.create!(name: 'Account Request', default_status_id: 1)
    @project.trackers << tracker
    other = Project.find(2)
    other.trackers << tracker
    configure_account_request_fields(trackers: [tracker], projects: [other])

    assert Config.autoconfigure_account_request!
    assert_equal other.id, Config.sources.first['project_id']
  end

  test 'autoconfigure does nothing when no project has the account request fields' do
    tracker = Tracker.create!(name: 'Account Request', default_status_id: 1)
    @project.trackers << tracker

    assert_not Config.autoconfigure_account_request!
    assert_equal [], Config.sources
  end

  test 'autoconfigure does nothing without an Account Request tracker' do
    assert_not Config.autoconfigure_account_request!
    assert_equal [], Config.sources
  end
end
