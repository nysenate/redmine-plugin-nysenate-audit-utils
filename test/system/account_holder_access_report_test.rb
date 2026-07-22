# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# Browser end-to-end tests for the Account Holder Access Report.
#
# This report renders "one row per account (account holder x target system)"
# with a derived active/inactive status. The web view collapses accounts to one
# row per holder and paginates; the CSV export is the flat, full, unpaginated
# set. All rows here come from SEEDED closed issues in the project (no ESS): the
# report service reads closed Add/Delete tickets via AccountTrackingService and
# derives status from the latest relevant ticket per holder+system.
#
# TEST DATA POLICY: every name / username / id below is obviously synthetic.
class AccountHolderAccessReportTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers, :issues

  # CSV header row emitted by CsvGenerator.generate_account_holder_access_csv
  # (after the metadata block). Asserted verbatim by the export test.
  CSV_HEADERS = [
    'Account Holder Name',
    'Account Holder Type',
    'Account Holder Username',
    'Account Holder Office',
    'Target System',
    'Account Status',
    'Request Code'
  ].freeze

  setup do
    @project = Project.find(1)
    @tracker = Tracker.find(1)

    # Map + register the standard Account Holder / request custom fields and
    # point ESS at the fake host; enable the audit_utils module.
    # Field creation touches the acts_positioned position column, which can
    # deadlock against concurrent runs on the shared test DB -- retry once.
    @fields = with_deadlock_retry { setup_standard_bachelp_fields(@tracker) }
    configure_ess!
    @project.enable_module!(:audit_utils)

    @closed_status = IssueStatus.where(is_closed: true).first

    log_user('admin', 'admin')
  end

  # 1. Web view: one row per account holder, each system listed within the row.
  def test_web_view_renders_row_per_account_holder_and_system
    # John has access to two systems -> one collapsed row carrying both.
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee', office: 'Chamber A')
    seed_account('900001', 'Ada Testwell', 'AIX', 'Add', uid: 'atestwell', type: 'Employee', office: 'Chamber A')
    # A second, separate holder on one system.
    seed_account('900002', 'Ben Sampleton', 'SFS', 'Add', uid: 'bsampleton', type: 'Vendor', office: 'Annex B')

    visit_report

    assert_selector 'h2', text: 'Account Holder Access Report'
    # Two holders -> two body rows.
    assert_selector 'table.list.account-holder-access tbody tr', count: 2
    # Ada's single row carries both systems and both derived request codes.
    assert_selector 'tbody tr td.col-system div.account-line', text: 'Oracle / SFMS'
    assert_selector 'tbody tr td.col-system div.account-line', text: 'AIX'
    assert_text 'Ada Testwell'
    assert_text 'atestwell'
    assert_text 'Chamber A'
    assert_text 'Ben Sampleton'
    # Request codes derive from system prefix + action suffix (USR+A, AIX+A).
    assert_selector 'td.col-code div.account-line', text: 'USRA'
    assert_selector 'td.col-code div.account-line', text: 'AIXA'
  end

  # 2a. Search box filters by account holder name OR username.
  def test_search_filter_narrows_by_name_or_username
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee')
    seed_account('900002', 'Ben Sampleton', 'AIX', 'Add', uid: 'bsampleton', type: 'Vendor')

    visit_report
    assert_selector 'tbody tr', count: 2

    # Search by username fragment.
    fill_in 'search', with: 'bsampleton'
    click_button 'Apply'

    assert_selector 'tbody tr', count: 1
    assert_text 'Ben Sampleton'
    assert_no_text 'Ada Testwell'
  end

  # 2b. Account Holder Type filter (auto-submits on change).
  def test_account_holder_type_filter
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee')
    seed_account('900002', 'Ben Sampleton', 'AIX', 'Add', uid: 'bsampleton', type: 'Vendor')

    visit_report
    assert_selector 'tbody tr', count: 2

    select 'Vendor', from: 'user_type'

    assert_selector 'tbody tr', count: 1
    assert_text 'Ben Sampleton'
    assert_no_text 'Ada Testwell'

    # 'Non-employee' matches any non-Employee type (i.e. the Vendor here).
    select 'Non-employee', from: 'user_type'
    assert_selector 'tbody tr', count: 1
    assert_text 'Ben Sampleton'
    assert_no_text 'Ada Testwell'

    # Back to Employee.
    select 'Employee', from: 'user_type'
    assert_selector 'tbody tr', count: 1
    assert_text 'Ada Testwell'
    assert_no_text 'Ben Sampleton'
  end

  # 2c. Target System filter (auto-submits on change).
  def test_target_system_filter
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee')
    seed_account('900002', 'Ben Sampleton', 'AIX', 'Add', uid: 'bsampleton', type: 'Employee')

    visit_report
    assert_selector 'tbody tr', count: 2

    select 'AIX', from: 'target_system'

    assert_selector 'tbody tr', count: 1
    assert_text 'Ben Sampleton'
    assert_no_text 'Ada Testwell'
  end

  # 2d. Account Status filter: default active-only, inactive-only, all.
  def test_account_status_filter
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee')
    # Removed holder: latest relevant action is Delete -> inactive.
    seed_account('900002', 'Ben Sampleton', 'AIX', 'Delete', uid: 'bsampleton', type: 'Employee')

    visit_report
    # Default is Active Only.
    assert_selector 'tbody tr', count: 1
    assert_text 'Ada Testwell'
    assert_no_text 'Ben Sampleton'

    select 'Inactive Only', from: 'account_status'
    assert_selector 'tbody tr', count: 1
    assert_text 'Ben Sampleton'
    assert_no_text 'Ada Testwell'
    # Inactive access is flagged when the report includes it.
    assert_selector 'span.account-status-inactive'

    select 'All Statuses', from: 'account_status'
    assert_selector 'tbody tr', count: 2
    assert_text 'Ada Testwell'
    assert_text 'Ben Sampleton'
  end

  # 3. Pagination preserves the active filter + sort across pages.
  def test_pagination_preserves_filter_and_sort
    # Seed 30 holders (> one 25-row page). Zero-padded names sort lexically.
    (1..30).each do |n|
      nn = format('%02d', n)
      seed_account("9500#{nn}", "Zeta Pagerow #{nn}", 'Oracle / SFMS', 'Add',
                   uid: "pagerow#{nn}", type: 'Employee')
    end

    # Apply a filter (search) AND a descending sort via the URL, then paginate.
    visit "/projects/#{@project.identifier}/audit_reports/account_holder_access?search=Pagerow&sort=user_name%3Adesc"

    # First page (25 rows), descending: "...30" is here, "...01" is not.
    assert_selector 'tbody tr', count: 25
    assert_text 'Zeta Pagerow 30'
    assert_no_text 'Zeta Pagerow 01'

    within 'span.pagination' do
      click_link '2'
    end

    # Page 2 carries the filter + sort in the URL...
    assert_includes page.current_url, 'page=2'
    assert_includes page.current_url, 'search=Pagerow'
    assert_includes page.current_url, 'sort=user_name'
    # ...and shows the tail of the descending set (05..01), not the head.
    assert_selector 'tbody tr', count: 5
    assert_text 'Zeta Pagerow 01'
    assert_no_text 'Zeta Pagerow 30'
  end

  # 4. CSV export contains the FULL, unpaginated, flat (one-row-per-account) set.
  def test_csv_export_contains_full_unpaginated_dataset
    # 30 holders on 25-per-page -> more than one page; CSV must contain all 30.
    (1..30).each do |n|
      nn = format('%02d', n)
      seed_account("9600#{nn}", "Cee Exportrow #{nn}", 'Oracle / SFMS', 'Add',
                   uid: "exportrow#{nn}", type: 'Employee', office: "Office #{nn}")
    end

    visit_report
    # The Excel export link lives next to the CSV link.
    assert_link 'Export Excel'
    # Web view is paginated to 25.
    assert_selector 'tbody tr', count: 25

    # The Playwright CSV parse would treat the metadata block as the header, so
    # parse headerless and locate the real header row + count data rows.
    rows = downloaded_csv('*.csv', headers: false) { click_link 'Export CSV' }.to_a
    header_index = rows.index { |r| r.first == 'Account Holder Name' }
    assert header_index, 'Expected an "Account Holder Name" header row in the CSV'

    assert_equal CSV_HEADERS, rows[header_index]

    data_rows = rows[(header_index + 1)..].reject { |r| r.compact.empty? }
    # Full unpaginated set: all 30 accounts (one row each), not just the page.
    assert_equal 30, data_rows.size
    names = data_rows.map(&:first)
    assert_includes names, 'Cee Exportrow 01'
    assert_includes names, 'Cee Exportrow 30'
  end

  # 5. Empty state: a filter matching nothing renders cleanly (no table, nodata).
  def test_empty_state_renders_cleanly
    seed_account('900001', 'Ada Testwell', 'Oracle / SFMS', 'Add', uid: 'atestwell', type: 'Employee')

    visit_report
    assert_selector 'tbody tr', count: 1

    fill_in 'search', with: 'no-such-holder-zzz'
    click_button 'Apply'

    assert_no_selector 'table.list.account-holder-access tbody tr'
    assert_selector 'p.nodata', text: /No account access found/
  end

  private

  def visit_report
    visit "/projects/#{@project.identifier}/audit_reports/account_holder_access"
  end

  # Retry a block once if the shared test DB deadlocks (a known race when other
  # runs create custom fields concurrently). NOTE: a shared-helper concern --
  # if setup_standard_bachelp_fields itself grew this retry, callers wouldn't
  # need it here.
  def with_deadlock_retry
    attempts = 0
    begin
      yield
    rescue ActiveRecord::Deadlocked
      attempts += 1
      raise if attempts > 2

      sleep(0.3 * attempts)
      retry
    end
  end

  # Seed a closed issue carrying the Account Holder / request custom fields the
  # report reads. Status is derived from the account_action of the latest closed
  # ticket per holder+system (Add => active, Delete => inactive).
  def seed_account(user_id, name, target_system, account_action, uid:, type:, office: nil)
    values = {
      @fields[:user_id].id => user_id.to_s,
      @fields[:user_name].id => name,
      @fields[:user_uid].id => uid,
      @fields[:user_type].id => type,
      @fields[:target_system].id => target_system,
      @fields[:account_action].id => account_action
    }
    values[@fields[:user_location].id] = office if office

    issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      author_id: 1,
      subject: "Account request for #{name} (#{target_system})",
      status: @closed_status,
      priority_id: 5,
      custom_field_values: values
    )
    # closed_on must be set for the report's closed-ticket query.
    Issue.where(id: issue.id).update_all(closed_on: Time.current - 1.day)
    issue.reload
  end
end
