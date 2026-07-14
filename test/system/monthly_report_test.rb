# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end (browser) tests for the Monthly Report + All-Systems Monthly ZIP.
#
# Unlike the autofill widget, the monthly report path does NOT call ESS: it
# reads account-status snapshots straight from *closed* issues in the DB via
# AccountTrackingService (Add => active, Delete => inactive; only the most
# recent Add/Delete per user/system counts). So these tests seed synthetic
# closed Account Request issues and assert the rendered snapshot + exports.
#
# All identity data here is obviously synthetic (fake names, 9000xx IDs).
class MonthlyReportTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers, :issues

  # closed_on far in the past so every snapshot cutoff (beginning of the
  # current month for monthly mode, "now" for current mode) includes them.
  FIXED_CLOSED_ON = Time.utc(2020, 1, 15, 12, 0, 0)

  setup do
    @project, @tracker, @fields = setup_audit_utils_project
    @closed_status = IssueStatus.where(is_closed: true).first

    # Seed synthetic closed Account Request issues.
    #   Oracle / SFMS: one active (Add) holder + one inactive (Delete) holder.
    #   AIX: one active holder (proves per-system filtering / a non-default tab).
    seed_closed_account_issue('900101', 'Ada Testwell', 'Oracle / SFMS', 'Add')
    seed_closed_account_issue('900102', 'Ben Sample',   'Oracle / SFMS', 'Delete')
    seed_closed_account_issue('900201', 'Cara Mockton', 'AIX',           'Add')

    log_in_as_admin
  end

  # 1. Web view: default target system (Oracle / SFMS) renders the snapshot
  #    table with the seeded active holder.
  def test_monthly_web_view_renders_snapshot_table_for_target_system
    visit monthly_path

    assert_selector 'h2', text: 'Monthly Report'
    # Default target system is the first configured value.
    assert_selector 'select#target_system option[selected]', text: 'Oracle / SFMS'

    within 'table.list.issues' do
      # Active Oracle holder shows; the Delete holder is hidden by the default
      # 'active' status filter.
      assert_text 'Ada Testwell'
      assert_text '900101'
      assert_no_text 'Ben Sample'
    end
  end

  # Switching the status filter to 'all' surfaces the inactive (Delete) holder.
  def test_monthly_web_view_all_statuses_shows_inactive_holder
    visit monthly_path(status_filter: 'all')

    within 'table.list.issues' do
      assert_text 'Ada Testwell'
      assert_text 'Ben Sample'
    end
  end

  # 2. Single-system CSV export: the "Export CSV" link streams the Oracle
  #    snapshot as CSV with the expected header row and a seeded data row.
  def test_single_system_csv_export
    visit monthly_path(target_system: 'Oracle / SFMS', status_filter: 'all')

    # Two "Export CSV..." links exist; match the single-system one exactly.
    rows = downloaded_csv('*.csv', headers: false) do
      click_link 'Export CSV', exact: true
    end

    header = rows.find { |r| r.include?('Account Holder Name') }
    assert header, "expected an 'Account Holder Name' header row in the CSV, got: #{rows.inspect}"
    ['Account Holder ID', 'Account Holder Type', 'Account Status',
     'Last Action', 'Request Code'].each do |col|
      assert_includes header, col
    end

    flat = rows.flatten.compact
    assert_includes flat, 'Ada Testwell'
    assert_includes flat, '900101'
    assert_includes flat, 'USRA' # Oracle prefix "USR" + Add suffix "A"
  end

  # 3. All-Systems Monthly ZIP: the "Export CSV All Systems" link streams a zip
  #    containing exactly one CSV per configured target system.
  def test_all_systems_monthly_zip_export
    visit monthly_path

    configured_systems = @fields[:target_system].possible_values
    expected_names = configured_systems.map { |s| "monthly_report_#{s.parameterize}_" }

    entries = downloaded_zip_entries('*.zip') do
      click_link 'Export CSV All Systems'
    end

    assert_equal configured_systems.size, entries.size,
                 "expected one CSV per configured system, got: #{entries.inspect}"
    assert entries.all? { |n| n.end_with?('.csv') }, "all zip entries should be CSVs: #{entries.inspect}"

    # Each configured system contributes a distinctly-named CSV.
    expected_names.each do |prefix|
      assert entries.any? { |n| n.start_with?(prefix) },
             "expected a zip entry starting with #{prefix.inspect}, got: #{entries.inspect}"
    end
  end

  # 4a. Empty state: a target system with no seeded data renders cleanly.
  def test_monthly_empty_state_for_system_without_data
    visit monthly_path(target_system: 'PayServ')

    assert_selector 'p.nodata', text: /No account data found for PayServ/
    assert_no_selector 'table.list.issues'
  end

  # 4b. Mode variant: 'current' mode (no time filtering) still renders the
  #     seeded active holder and hides the month/year selector.
  def test_monthly_current_mode_renders_without_month_selector
    visit monthly_path(mode: 'current', target_system: 'Oracle / SFMS')

    assert_selector 'input#mode_current[checked]'
    assert_no_selector '#month-selector'
    within 'table.list.issues' do
      assert_text 'Ada Testwell'
    end
  end

  private

  def monthly_path(params = {})
    query = params.empty? ? '' : "?#{params.to_query}"
    "/projects/#{@project.identifier}/audit_reports/monthly#{query}"
  end

  # Create a *closed* Account Request issue carrying the account-holder /
  # request custom fields, then backdate closed_on (bypassing callbacks) so it
  # falls before any snapshot cutoff.
  def seed_closed_account_issue(user_id, user_name, target_system, account_action)
    issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Account Request for #{user_name}",
      status: @closed_status,
      priority_id: 5,
      custom_field_values: {
        @fields[:user_id].id => user_id,
        @fields[:user_name].id => user_name,
        @fields[:target_system].id => target_system,
        @fields[:account_action].id => account_action
      }
    )
    Issue.where(id: issue.id).update_all(closed_on: FIXED_CLOSED_ON)
    issue
  end
end
