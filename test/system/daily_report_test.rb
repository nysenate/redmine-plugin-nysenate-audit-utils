# frozen_string_literal: true

require File.expand_path('../system_test_helper', __dir__)

# End-to-end browser tests for the Daily Report:
#   * the Reports (Audit Reports) landing/index page and its report links,
#   * the daily report web view in both "Last Business Day" and "Date Range"
#     modes (rows come from the stubbed ESS statusChanges fixture),
#   * the "Export CSV" download, and
#   * the empty state when ESS reports no status changes.
#
# ESS is stubbed in-process via WebMock (see AuditUtilsSystemTestCase). The
# status-change fixture (test/fixtures/status_changes_response.json) contains
# four synthetic employees; one of them (900104, transaction code "LOC") is not
# a recognized transaction code and is filtered out by EssStatusChangeService,
# so the report renders THREE rows:
#   900101 Doodlewick, Ulric F. (APP)
#   900102 Bafflegab, Verena G., III (APP)
#   900103 Quibbleton, Wystan (EMP)
class DailyReportTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  setup do
    @project, @tracker, @field_map = setup_audit_utils_project
    stub_ess_status_changes
    log_in_as_admin
  end

  # 1. Report index nav ------------------------------------------------------
  def test_reports_index_links_to_each_report
    visit project_audit_reports_path(@project)

    assert_selector 'h2', text: 'Audit Reports'
    assert_link 'Daily Report'
    assert_link 'Weekly Report'
    assert_link 'Monthly Report'

    # The Daily Report link actually lands on the daily report.
    click_link 'Daily Report'
    assert_selector 'h2', text: 'Daily Report'
  end

  # 2a. Daily report web view -- Last Business Day (default) mode -------------
  def test_daily_report_business_day_view_renders_rows
    visit daily_project_audit_reports_path(@project)

    assert_selector 'h2', text: 'Daily Report'
    # Business-day mode is the default and its radio is selected.
    assert find('#mode_business_day').checked?
    assert_text 'Last business day ending'

    # Exactly the three recognized-transaction employees are listed.
    assert_selector 'table.daily-report-table tbody tr', count: 3
    within 'table.daily-report-table' do
      assert_text 'Doodlewick, Ulric F.'
      assert_text 'Bafflegab, Verena G., III'
      assert_text 'Quibbleton, Wystan'
      # 900104 (LOC) is not a recognized transaction code -> filtered out.
      assert_no_text 'Frobshaw'
    end
    assert_text 'Showing 3 users with status changes'
  end

  # 2b. Daily report web view -- explicit Date Range mode --------------------
  def test_daily_report_date_range_view_renders_rows
    visit daily_project_audit_reports_path(@project,
      mode: 'range', start_date: '2026-07-01', end_date: '2026-07-10')

    assert find('#mode_range').checked?
    assert_text 'Date range: 2026-07-01 to 2026-07-10'
    assert_selector 'table.daily-report-table tbody tr', count: 3
    assert_text 'Doodlewick, Ulric F.'
  end

  # 3. CSV export ------------------------------------------------------------
  def test_daily_report_export_csv
    visit daily_project_audit_reports_path(@project)

    # The Excel export link lives next to the CSV link.
    assert_link 'Export Excel'

    # The daily CSV starts with metadata rows before the column header, so parse
    # without a header row and search the raw cells.
    rows = downloaded_csv('*.csv', headers: false) { click_link 'Export CSV' }
    cells = rows.flatten

    # Column header row is present...
    assert_includes cells, 'Account Holder Name'
    assert_includes cells, 'Account Holder ID'
    assert_includes cells, 'Status Changes'
    # ...and at least one synthetic data row landed in the export.
    assert_includes cells, 'Doodlewick, Ulric F.'
    assert_includes cells, '900101'
  end

  # 4. Empty state -----------------------------------------------------------
  def test_daily_report_empty_state
    # Re-stub statusChanges to return no results (last WebMock stub wins).
    stub_ess_status_changes_empty

    visit daily_project_audit_reports_path(@project,
      mode: 'range', start_date: '2026-06-01', end_date: '2026-06-02')

    assert_selector 'p.nodata', text: /No user status changes found/
    assert_no_selector 'table.daily-report-table'
  end

  private

  # Stub the ESS statusChanges endpoint with an empty (but successful) result so
  # the daily report renders its empty state rather than an error page.
  def stub_ess_status_changes_empty
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/statusChanges}o)
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { success: true, result: [] }.to_json
      )
  end
end
