# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require 'zip'

class TriennialReportTest < ActionController::TestCase
  tests AuditReportsController
  fixtures :users, :roles, :projects, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :members, :member_roles, :enabled_modules, :issues

  def setup
    @request.session[:user_id] = 1
    Project.find(1).enable_module!(:audit_utils)
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' },
        { 'project_id' => '2', 'tracker_id' => '2', 'mapping_mode' => 'tracker', 'code' => '' }
      ]
    }
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  def make_issue(project_id:, tracker_id:, created_on: Date.current - 10)
    issue = Issue.create!(project_id: project_id, tracker_id: tracker_id, author_id: 1, status_id: 1,
                          subject: "Triennial #{project_id}/#{tracker_id}")
    Issue.where(id: issue.id).update_all(created_on: created_on.in_time_zone.change(hour: 12))
    issue
  end

  test 'lists tickets across sources grouped by request code' do
    coded = make_issue(project_id: 1, tracker_id: 1)
    uncoded = make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1 }

    assert_response :success
    assert_select 'h2', text: 'Triennial Audit Report'
    assert_equal ['BUGA', 'No request code'],
                 css_select('table.triennial-report-table tr.group .name').map(&:text)
    assert_select 'table.triennial-report-table a[href=?]', "/issues/#{coded.id}"
    assert_select 'table.triennial-report-table a[href=?]', "/issues/#{uncoded.id}"
    headers = css_select('table.triennial-report-table thead th').map { |th| th.text.strip }
    assert_equal ['Request Code', 'Subject', 'Ticket #', 'Open Date', 'Closed Date',
                  'Ticket Status', 'Selected for Audit'], headers
  end

  test 'group counts are totals across pages' do
    3.times { make_issue(project_id: 1, tracker_id: 1, created_on: Date.new(2020, 5, 5)) }
    window = { project_id: 1, start_date: '2020-05-01', end_date: '2020-05-31', per_page: 2 }

    with_settings per_page_options: '2,25' do
      get :triennial, params: window
      assert_equal ['3'], css_select('tr.group .count').map(&:text)

      get :triennial, params: window.merge(page: 2)
      assert_equal ['3'], css_select('tr.group .count').map(&:text)
    end
  end

  test 'filters by the open date range' do
    inside = make_issue(project_id: 1, tracker_id: 1, created_on: Date.new(2026, 3, 10))
    outside = make_issue(project_id: 1, tracker_id: 1, created_on: Date.new(2026, 4, 10))

    get :triennial, params: { project_id: 1, start_date: '2026-03-01', end_date: '2026-03-31' }

    assert_select 'a[href=?]', "/issues/#{inside.id}"
    assert_select 'a[href=?]', "/issues/#{outside.id}", count: 0
    assert_select 'input[name=start_date][value=?]', '2026-03-01'
  end

  test 'shows per-source errors above the rest of the report' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [
        { 'project_id' => '999', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'X' },
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }
      ]
    }
    issue = make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert_response :success
    assert_select '.triennial-source-errors li', text: /project #999/
    assert_select 'a[href=?]', "/issues/#{issue.id}"
  end

  test 'points admins at the settings when no sources are configured' do
    Setting.plugin_nysenate_audit_utils = {}

    get :triennial, params: { project_id: 1 }

    assert_response :success
    assert_select '.nodata a[href=?]', '/settings/plugin/nysenate_audit_utils'
  end

  test 'shows an error for an inverted date range' do
    get :triennial, params: { project_id: 1, start_date: '2026-03-31', end_date: '2026-03-01' }

    assert_response :success
    assert_select 'h2', text: 'Triennial Audit Report', count: 0
    assert_match(/Start date must be before end date/, response.body)
  end

  test 'is linked from the reports index' do
    get :index, params: { project_id: 1 }

    assert_select 'a[href=?]', '/projects/ecookbook/audit_reports/triennial'
  end

  test 'requires view_audit_reports' do
    @request.session[:user_id] = 2
    Role.find(1).remove_permission!(:view_audit_reports)

    get :triennial, params: { project_id: 1 }

    assert_response :forbidden
  end

  def option(select, value)
    css_select("select##{select} option[value=\"#{value}\"]").first
  end

  test 'banner counts project/tracker pairs instead of listing them' do
    make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert_select '.report-info', text: /across 2 project\/tracker pairs\./
    assert_select '.report-info', text: /#{Regexp.escape(Project.find(1).name)}/, count: 0
  end

  test 'code and project/tracker filters disable contradictory options' do
    make_issue(project_id: 1, tracker_id: 1) # BUGA
    make_issue(project_id: 2, tracker_id: 2) # no code

    get :triennial, params: { project_id: 1, source: '1-1' }
    assert option('source', '1-1')['selected']
    assert_nil option('code', 'BUGA')['disabled']
    assert option('code', '__none__')['disabled'], 'no uncoded tickets in project 1 / tracker 1'
    assert_select '.report-info', text: /in #{Regexp.escape(Project.find(1).name)} \/ Bug/

    get :triennial, params: { project_id: 1, code: 'BUGA' }
    assert_nil option('source', '1-1')['disabled']
    assert option('source', '2-2')['disabled'], 'no BUGA tickets in project 2 / tracker 2'
    assert_select 'tr.group .name', text: 'BUGA'
    assert_select 'tr.group .name', text: 'No request code', count: 0
  end

  test 'a selected filter option stays enabled even when it matches nothing' do
    make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1, source: '2-2', code: 'BUGA' }

    assert_nil option('source', '2-2')['disabled']
    assert_nil option('code', 'BUGA')['disabled']
    assert_select '.nodata', text: /No tickets match the selected filters/
  end

  test 'search matches ticket number, code or subject' do
    coded = make_issue(project_id: 1, tracker_id: 1)
    other = make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1, search: "##{other.id}" }
    assert_select 'a[href=?]', "/issues/#{other.id}"
    assert_select 'a[href=?]', "/issues/#{coded.id}", count: 0

    get :triennial, params: { project_id: 1, search: 'buga' }
    assert_select 'a[href=?]', "/issues/#{coded.id}"
    assert_select 'a[href=?]', "/issues/#{other.id}", count: 0
    assert_select 'td.code-col span.highlight', text: 'BUGA'
  end
  test 'exports the filtered report as xlsx' do
    coded = make_issue(project_id: 1, tracker_id: 1)
    make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1, start_date: '2026-01-01', end_date: '2026-09-30', code: 'BUGA' },
                    format: :xlsx

    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type
    assert_match(/triennial_audit_20260101_20260930\.xlsx/, response.headers['Content-Disposition'])
    xml = nil
    Zip::File.open_buffer(response.body) { |z| xml = z.read('xl/worksheets/sheet1.xml') }
    assert_includes xml, 'Request Code: BUGA'
    assert_includes xml, coded.subject
    assert_not_includes xml, 'Triennial 2/2', 'only the BUGA ticket is exported'
  end

  test 'export link carries the current filters' do
    get :triennial, params: { project_id: 1, source: '1-1', search: 'foo' }

    assert_select 'a.icon-download[href*=?]', 'triennial.xlsx' do |links|
      href = links.first['href']
      assert_includes href, 'source=1-1'
      assert_includes href, 'search=foo'
      assert_not_includes href, 'code='
    end
  end
  def with_selected_field
    field = IssueCustomField.create!(name: 'Triennial Selected', field_format: 'list',
                                     possible_values: %w[No 2025], default_value: 'No',
                                     is_for_all: true, trackers: Tracker.all)
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'selected_for_audit_field_id' => field.id.to_s
    )
    field
  end

  test 'shows checkboxes and the year selector when Selected for Audit is configured' do
    with_selected_field
    issue = make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert_select 'form#triennial-flag-form[action=?]', '/projects/ecookbook/audit_reports/flag_triennial_selections'
    assert_select 'select#year option', %w[2025 No].size
    assert_select 'input[type=checkbox][name=?][value=?]', 'issue_ids[]', issue.id.to_s
    assert_select 'input#triennial-select-all'

    get :triennial, params: { project_id: 1, year: 'No' }
    assert option('year', 'No')['selected'], 'keeps the year chosen before a flag'
  end

  test 'hides flagging when Selected for Audit is not configured' do
    make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert_select 'input[name=?]', 'issue_ids[]', count: 0
    assert_select '.triennial-flag-bar', text: /Configure the Selected for Audit custom field/
  end

  test 'flag selected sets the field and returns to the filtered report' do
    field = with_selected_field
    issue = make_issue(project_id: 1, tracker_id: 1)

    post :flag_triennial_selections,
         params: { project_id: 1, issue_ids: [issue.id], year: '2025', code: 'BUGA', page: '2' }

    assert_redirected_to '/projects/ecookbook/audit_reports/triennial?code=BUGA&page=2&year=2025'
    assert_equal '2025', issue.reload.custom_field_value(field)
    assert_equal 'Set Selected for Audit to 2025 on 1 ticket.', flash[:notice]
  end

  test 'flag selected reports tickets it could not flag' do
    with_selected_field
    issue = make_issue(project_id: 1, tracker_id: 1)
    outside = Issue.find(1) # moved to tracker 3, which is not a configured source
    outside.update_column(:tracker_id, 3)

    post :flag_triennial_selections, params: { project_id: 1, issue_ids: [issue.id, outside.id], year: '2025' }

    assert_match(/Could not flag 1 ticket: ##{outside.id} \(not in a Triennial Audit source\)/, flash[:error])
    assert_match(/on 1 ticket/, flash[:notice])
  end

  test 'flag selected with nothing checked' do
    with_selected_field

    post :flag_triennial_selections, params: { project_id: 1, year: '2025' }

    assert_redirected_to '/projects/ecookbook/audit_reports/triennial?year=2025'
    assert_equal 'Select at least one ticket to flag.', flash[:error]
  end

  test 'flag selected requires view_audit_reports' do
    with_selected_field
    issue = make_issue(project_id: 1, tracker_id: 1)
    @request.session[:user_id] = 2
    Role.find(1).remove_permission!(:view_audit_reports)

    post :flag_triennial_selections, params: { project_id: 1, issue_ids: [issue.id], year: '2025' }

    assert_response :forbidden
  end
  test 'filters by Selected for Audit and disables contradictory options' do
    field = with_selected_field
    # A 2020 window keeps the fixture issues (no value, so "No") out.
    window = { project_id: 1, start_date: '2020-05-01', end_date: '2020-05-31' }
    flagged = make_issue(project_id: 1, tracker_id: 1, created_on: Date.new(2020, 5, 5))
    flagged.reload.update!(custom_field_values: { field.id.to_s => '2025' })
    unflagged = make_issue(project_id: 2, tracker_id: 2, created_on: Date.new(2020, 5, 5))

    get :triennial, params: window.merge(selected: '2025')
    assert_select 'a[href=?]', "/issues/#{flagged.id}"
    assert_select 'a[href=?]', "/issues/#{unflagged.id}", count: 0
    assert option('source', '2-2')['disabled'], 'no 2025 tickets in project 2 / tracker 2'
    assert_select 'a.icon-download[href*=?]', 'selected=2025'

    assert_select '.report-info', text: /across 1 project\/tracker pair \(filtered\)\./

    get :triennial, params: window.merge(source: '1-1')
    assert_nil option('selected', '2025')['disabled']
    assert option('selected', 'No')['disabled'], 'every project 1 / tracker 1 ticket is 2025'
  end

  test 'Selected for Audit No includes tickets with no value set' do
    field = with_selected_field
    no = make_issue(project_id: 1, tracker_id: 1) # defaults to No
    unset = make_issue(project_id: 2, tracker_id: 2)
    CustomValue.where(customized: unset, custom_field: field).delete_all

    get :triennial, params: { project_id: 1, selected: 'No' }

    assert_select 'a[href=?]', "/issues/#{no.id}"
    assert_select 'a[href=?]', "/issues/#{unset.id}"
    assert_equal ['Any', 'No', '2025'], css_select('select#selected option').map(&:text)
  end

  test 'flag selected keeps the Selected for Audit filter' do
    with_selected_field
    issue = make_issue(project_id: 1, tracker_id: 1)

    post :flag_triennial_selections, params: { project_id: 1, issue_ids: [issue.id], year: '2025', selected: 'No' }

    assert_redirected_to '/projects/ecookbook/audit_reports/triennial?selected=No&year=2025'
  end

  test 'warns when Selected for Audit has no option for the To year' do
    field = with_selected_field # No, 2025

    get :triennial, params: { project_id: 1, start_date: '2024-01-01', end_date: '2026-06-30' }
    assert_select '.triennial-year-warning', text: /has no year option that covers 2026 \(its latest is 2025\)\./
    assert_select '.triennial-year-warning a[href=?]', "/custom_fields/#{field.id}/edit"

    get :triennial, params: { project_id: 1, start_date: '2024-01-01', end_date: '2025-12-31' }
    assert_select '.triennial-year-warning', count: 0
  end

  test 'year warning tells non-admins to contact an administrator' do
    with_selected_field
    @request.session[:user_id] = 2
    Role.find(1).add_permission!(:view_audit_reports)

    get :triennial, params: { project_id: 1, start_date: '2024-01-01', end_date: '2026-06-30' }

    assert_select '.triennial-year-warning', text: /Contact a Redmine administrator to add additional years to the Triennial Selected field\./
    assert_select '.triennial-year-warning a', count: 0
  end

  test 'no year warning when Selected for Audit is not configured' do
    get :triennial, params: { project_id: 1 }

    assert_select '.triennial-year-warning', count: 0
  end
  # dlopper (user 3): Developer on project 1 only (not a member of private project 2).
  def as_developer
    @request.session[:user_id] = 3
    Role.find(2).add_permission!(:view_audit_reports)
  end

  test 'shows the missing permissions instead of a partial report' do
    as_developer
    make_issue(project_id: 1, tracker_id: 1)
    make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1 }

    assert_response :success
    assert_select '.triennial-permission-errors li', text: "View issues in #{Project.find(2).name}"
    assert_select 'table.triennial-report-table', count: 0
    assert_select '.report-info', count: 0
    assert_select 'a.icon-download', count: 0
  end

  test 'refuses the xlsx export when the user cannot see every ticket' do
    as_developer
    make_issue(project_id: 2, tracker_id: 2)

    get :triennial, params: { project_id: 1 }, format: :xlsx

    assert_response :forbidden
    assert_equal 'text/plain', response.media_type
    assert_match(/View issues in #{Project.find(2).name}/, response.body)
  end

  test 'shows the report to a non-admin who can see every ticket' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [{ 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }]
    }
    as_developer
    issue = make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert_select '.triennial-permission-errors', count: 0
    assert_select 'a[href=?]', "/issues/#{issue.id}"
  end

  test 'disables the checkbox on tickets the user cannot edit' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [{ 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }]
    }
    with_selected_field
    as_developer
    Role.find(2).remove_permission!(:edit_issues)
    issue = make_issue(project_id: 1, tracker_id: 1)

    get :triennial, params: { project_id: 1 }

    assert css_select("input#issue-#{issue.id}").first['disabled']
  end

  test 'flag selected refuses the whole submission if any ticket cannot be edited' do
    Setting.plugin_nysenate_audit_utils = {
      'triennial_audit_sources' => [{ 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }]
    }
    field = with_selected_field
    as_developer
    Role.find(2).remove_permission!(:edit_issues)
    issue = make_issue(project_id: 1, tracker_id: 1)

    post :flag_triennial_selections, params: { project_id: 1, issue_ids: [issue.id], year: '2025' }

    assert_equal 'No', issue.reload.custom_field_value(field)
    assert_match(/\ANothing was flagged\. You need permission to view and edit every selected ticket: ##{issue.id} /,
                 flash[:error])
    assert_nil flash[:notice]
  end
end
