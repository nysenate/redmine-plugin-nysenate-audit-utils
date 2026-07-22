# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end (browser) tests for the Weekly audit report.
#
# The Weekly report is driven ENTIRELY by CLOSED Redmine issues whose
# `closed_on` falls within the selected window (no ESS involved), so these
# tests seed synthetic closed issues with the standard Account Holder custom
# fields and then drive the web view + CSV export through the browser.
class WeeklyReportTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers, :issues

  setup do
    # Maps the standard Account Holder / request custom fields onto tracker 1,
    # points ESS at the fake host, and enables the audit_utils module.
    @project, @tracker, @fields = setup_audit_utils_project
    log_in_as_admin
  end

  # ---------------------------------------------------------------------------
  # 1. Web view renders the table with a seeded closed ticket in the window.
  # ---------------------------------------------------------------------------
  def test_web_view_renders_table_with_seeded_closed_ticket
    issue = seed_closed_weekly_issue

    visit weekly_url

    assert_selector 'table.weekly-report-table'
    within 'table.weekly-report-table' do
      assert_text "##{issue.id}"
      assert_text 'Zeta Fakeholder SFMS Add'   # subject
      assert_text 'Zeta Fakeholder'            # Account Holder Name
      assert_text '900123'                     # Account Holder ID
      assert_text 'zfakeholder'                # Account Holder Username
      assert_text 'Fake Office 9'              # Account Holder Office
      assert_text 'USRA'                       # Request Code (Oracle/SFMS + Add)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. CSV export: assert the legacy weekly headers + the seeded row.
  # ---------------------------------------------------------------------------
  def test_csv_export_includes_headers_and_seeded_row
    issue = seed_closed_weekly_issue

    visit weekly_url

    # The Excel export link lives next to the CSV link.
    assert_link 'Export Excel'

    # The weekly CSV carries a metadata preamble before the header row, so parse
    # raw (headers: false) and locate the real header row ourselves.
    rows = downloaded_csv(headers: false) { click_link 'Export CSV' }
    header = rows.find { |r| r.first == 'Ticket #' }

    assert header, "Expected a 'Ticket #' header row in the CSV (saw: #{rows.first(6).inspect})"
    %w[Account\ Holder\ Type Account\ Holder\ Name Account\ Holder\ Username
       Account\ Holder\ ID Account\ Holder\ Office Request\ Code
       Ticket\ Description Status Open\ Date Close\ Date Updated\ On].each do |col|
      assert_includes header, col
    end

    data_row = rows.find { |r| r.first.to_s == issue.id.to_s }
    assert data_row, "Expected a CSV data row for issue ##{issue.id}"
    assert_includes data_row, 'Zeta Fakeholder'
    assert_includes data_row, '900123'
    assert_includes data_row, 'zfakeholder'
    assert_includes data_row, 'USRA'
    assert_includes data_row, 'Zeta Fakeholder SFMS Add'
  end

  # ---------------------------------------------------------------------------
  # 3. Empty state: a window with no closed tickets renders cleanly.
  # ---------------------------------------------------------------------------
  def test_empty_state_renders_cleanly
    seed_closed_weekly_issue # exists but falls OUTSIDE the empty window below

    visit weekly_url(start_date: '2001-01-01', end_date: '2001-01-07')

    assert_no_selector 'table.weekly-report-table'
    assert_selector 'p.nodata', text: 'No closed tickets found for the selected period.'
  end

  private

  # URL for the weekly report, defaulting to a window that comfortably contains
  # issues closed "a couple days ago".
  def weekly_url(start_date: (Date.current - 7).iso8601, end_date: Date.current.iso8601)
    "/projects/#{@project.identifier}/audit_reports/weekly?start_date=#{start_date}&end_date=#{end_date}"
  end

  # Seed one CLOSED issue (status 5 = closed) with obviously-synthetic Account
  # Holder data, closed 2 days ago so it lands in the default weekly window.
  def seed_closed_weekly_issue
    issue = Issue.new(project: @project, tracker_id: @tracker.id, author_id: 1,
                      status_id: 5, subject: 'Zeta Fakeholder SFMS Add')
    issue.custom_field_values = {
      @fields[:user_type].id     => 'Employee',
      @fields[:user_id].id       => '900123',
      @fields[:user_name].id     => 'Zeta Fakeholder',
      @fields[:user_uid].id      => 'zfakeholder',
      @fields[:user_location].id => 'Fake Office 9',
      @fields[:account_action].id => 'Add',
      @fields[:target_system].id  => 'Oracle / SFMS'
    }
    issue.save!
    close_time = 2.days.ago
    Issue.where(id: issue.id).update_all(created_on: 6.days.ago,
                                         updated_on: close_time, closed_on: close_time)
    issue
  end
end
