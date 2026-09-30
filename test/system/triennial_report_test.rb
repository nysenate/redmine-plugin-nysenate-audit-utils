# frozen_string_literal: true

require File.expand_path('../system_test_helper', __dir__)

# End-to-end (browser) tests for the Triennial Audit Report: the Flag Selected
# round trip (check tickets, confirm, see them flagged) and the Excel export.
# No ESS -- the report reads tickets from the configured project/tracker
# sources only.
class TriennialReportSystemTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  setup do
    @project = Project.find(1)
    @project.enable_module!(:audit_utils)
    @field = IssueCustomField.create!(
      name: 'Selected for Audit', field_format: 'list', possible_values: %w[No 2022 2025],
      default_value: 'No', is_for_all: true, trackers: [Tracker.find(1)]
    )
    Setting.plugin_nysenate_audit_utils = {
      'selected_for_audit_field_id' => @field.id.to_s,
      'triennial_audit_sources' => [
        { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }
      ]
    }
    log_in_as_admin
  end

  def test_flag_selected_sets_the_year_on_checked_tickets
    picked = seed_issue('Zelda Triennial pick')
    skipped = seed_issue('Yusuf Triennial skip')

    visit triennial_url

    check "issue-#{picked.id}"
    assert_text '1 selected'
    select '2022', from: 'year'
    accept_confirm('Set Selected for Audit to 2022 on 1 ticket?') { click_button 'Flag Selected' }

    assert_text 'Set Selected for Audit to 2022 on 1 ticket.'
    assert_equal '2022', picked.reload.custom_field_value(@field)
    assert_equal 'No', skipped.reload.custom_field_value(@field)

    # The flagged ticket now matches the Selected for Audit filter.
    select '2022', from: 'selected'
    click_button 'Apply'
    within 'table.triennial-report-table' do
      assert_text 'Zelda Triennial pick'
      assert_no_text 'Yusuf Triennial skip'
    end
  end

  def test_dismissing_the_confirm_flags_nothing_and_leaves_the_form_usable
    issue = seed_issue('Xavi Triennial dismiss')

    visit triennial_url
    check "issue-#{issue.id}"
    dismiss_confirm { click_button 'Flag Selected' }

    assert_equal 'No', issue.reload.custom_field_value(@field)
    # Core's double-submit guard must not have locked the form.
    accept_confirm { click_button 'Flag Selected' }
    assert_text 'Set Selected for Audit to 2025 on 1 ticket.'
  end

  def test_excel_export_lists_the_report_tickets
    issue = seed_issue('Wanda Triennial export')

    visit triennial_url

    rows = downloaded_xlsx_rows('triennial_audit_*.xlsx') { click_link 'Export Excel' }
    header = rows.find { |r| r.first == 'Request Code' }
    assert header, 'expected a header row'
    row = rows.find { |r| r[header.index('Ticket #')].to_s == issue.id.to_s }
    assert row, "expected a row for ##{issue.id}"
    assert_equal 'BUGA', row[header.index('Request Code')]
    assert_equal 'Wanda Triennial export', row[header.index('Subject')]
  end

  private

  def triennial_url
    "/projects/#{@project.identifier}/audit_reports/triennial"
  end

  def seed_issue(subject)
    Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 1, subject: subject)
  end
end
