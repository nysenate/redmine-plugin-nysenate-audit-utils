# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end (browser) authorization tests for the Audit Utils plugin.
#
# Purpose: prove that every project surface the plugin adds is gated by the
# right project permission AND by the `audit_utils` module. Admin bypasses all
# `allowed_to?` checks, so these tests exclusively drive NON-admin members
# seeded with an exact permission subset via the base-class helpers
# (`create_member_with_permissions` / `log_in_with_permissions`).
#
# Each test pairs a negative (denied/absent) with a positive control (the same
# surface IS available once the gating permission is granted) so a silently
# broken assertion can't pass unnoticed.
#
# Redmine renders a denied action as a 403 error page carrying the text
# "You are not authorized to access this page." We assert on that text (and, by
# extension, that the guarded UI never appears).
class AuthorizationTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers, :issues

  NOT_AUTHORIZED_TEXT = 'You are not authorized to access this page.'

  setup do
    # Maps the standard Account Holder / request custom fields onto tracker 1,
    # points ESS at the fake host, and enables the audit_utils module on
    # project 1. Individual tests grant permission subsets on top of this.
    @project, @tracker, @fields = setup_audit_utils_project
  end

  # ===========================================================================
  # 1. Reports (index / daily) -- gated by :view_audit_reports
  # ===========================================================================

  def test_reports_denied_without_view_audit_reports_permission
    log_in_with_permissions([]) # member, but no audit permissions

    visit reports_index_url
    assert_text NOT_AUTHORIZED_TEXT
    assert_no_selector 'h2', text: 'Audit Reports'

    visit daily_report_url
    assert_text NOT_AUTHORIZED_TEXT
  end

  def test_reports_allowed_with_view_audit_reports_permission # positive control
    log_in_with_permissions([:view_audit_reports])

    visit reports_index_url
    assert_no_text NOT_AUTHORIZED_TEXT
    assert_selector 'h2', text: 'Audit Reports'
    assert_link 'Daily Report'
    assert_link 'Weekly Report'
  end

  def test_reports_menu_item_hidden_without_permission_and_shown_with
    # Absent for a member lacking the permission ...
    log_in_with_permissions([])
    visit project_overview_url
    within '#main-menu' do
      assert_no_link 'Reports'
    end

    # ... and present once the permission is granted (proves the assertion above
    # is meaningful and not just a bad selector).
    page.reset_session!
    log_in_with_permissions([:view_audit_reports])
    visit project_overview_url
    within '#main-menu' do
      assert_link 'Reports'
    end
  end

  # ===========================================================================
  # 2. CSV export -- gated by :view_audit_reports
  # ===========================================================================
  #
  # Each report's CSV comes from its own report action rendered with
  # `format: :csv` (e.g. AuditReportsController#weekly's `format.csv` block), so
  # it is protected by :view_audit_reports -- the SAME `before_action :authorize`
  # that guards the HTML report. There is no separate export permission.
  #
  # NOTE ON TECHNIQUE: we can't `visit` the `.csv` URL to assert a 403 -- the
  # Playwright driver fires "Download is starting" for ANY navigation to a
  # text/csv response (the denied 403 carries a text/csv content type too). So
  # the denial is proven on the HTML report (a member without the permission is
  # refused the whole report, hence its CSV), and the positive control downloads
  # the CSV via the on-page "Export CSV" link (a click-triggered download).
  def test_csv_export_is_gated_by_view_audit_reports
    # A member without :view_audit_reports gets neither the report nor its CSV.
    log_in_with_permissions([])
    visit weekly_report_url
    assert_text NOT_AUTHORIZED_TEXT
    assert_no_link 'Export CSV'

    # :view_audit_reports opens the report AND its CSV export (positive control).
    page.reset_session!
    log_in_with_permissions([:view_audit_reports])
    visit weekly_report_url
    assert_no_text NOT_AUTHORIZED_TEXT
    assert_link 'Export CSV'

    path = capture_download('weekly_report_*.csv') { click_link 'Export CSV' }
    assert File.size?(path), "Expected a non-empty weekly CSV download at #{path}"
  end

  # ===========================================================================
  # 3. Autofill widget -- gated by :use_user_autofill (+ module)
  # ===========================================================================

  def test_autofill_widget_absent_without_permission_present_with
    stub_ess_employee_search # in case the widget's assets probe ESS on load

    # add_issues lets the member reach the new-issue form, but WITHOUT
    # use_user_autofill the hook renders nothing.
    log_in_with_permissions([:add_issues])
    visit new_issue_url
    assert_selector 'form#issue-form' # form itself rendered
    assert_no_selector '#user-search-widget'

    # Grant use_user_autofill -> widget appears (positive control).
    page.reset_session!
    log_in_with_permissions([:add_issues, :use_user_autofill])
    visit new_issue_url
    assert_selector '#user-search-widget'
  end

  # ===========================================================================
  # 4. Create Packet button -- gated by issue/attachment visibility
  # ===========================================================================
  #
  # Packet creation is deliberately not a separate permission. The button is
  # injected by AttachmentsHelperPatch, which shows it whenever the issue has
  # attachments the user may view (`attachments_visible?` -> :view_issues). The
  # PacketCreationController authorizes via `@issue.visible?` /
  # `attachments_visible?`, and the context-menu hook checks :view_issues.
  #
  # This test documents that gate: a member with only :view_issues sees the
  # button on an issue WITH attachments, and the button is absent on an issue
  # WITHOUT attachments even though nothing else changed.
  def test_create_packet_button_tracks_view_issues_and_attachments
    set_tmp_attachments_directory
    issue_with_attachment = seed_issue('Packet gating - with attachment')
    Attachment.create!(container: issue_with_attachment,
                       file: uploaded_test_file('testfile.txt', 'text/plain'),
                       author: User.find(1))
    issue_without_attachment = seed_issue('Packet gating - no attachment')

    # Member has view_issues but explicitly NOT create_packet.
    log_in_with_permissions([:view_issues])

    visit "/issues/#{issue_with_attachment.id}"
    assert_selector "a[href*='/create_packet']", visible: :all,
                    text: 'Create Packet'

    visit "/issues/#{issue_without_attachment.id}"
    assert_no_selector "a[href*='/create_packet']", visible: :all
  end

  # ===========================================================================
  # 5. Vendor/Volunteer management -- gated by :manage_tracked_users
  # ===========================================================================

  def test_tracked_users_denied_without_manage_permission
    log_in_with_permissions([])

    visit tracked_users_url
    assert_text NOT_AUTHORIZED_TEXT
    assert_no_selector 'h2', text: 'Manage Vendors/Volunteers'

    visit project_overview_url
    within '#main-menu' do
      assert_no_link 'Manage Vendors/Volunteers'
    end
  end

  def test_tracked_users_allowed_with_manage_permission # positive control
    log_in_with_permissions([:manage_tracked_users])

    visit tracked_users_url
    assert_no_text NOT_AUTHORIZED_TEXT
    assert_selector 'h2', text: 'Manage Vendors/Volunteers'

    visit project_overview_url
    within '#main-menu' do
      assert_link 'Manage Vendors/Volunteers'
    end
  end

  # ===========================================================================
  # 6. Module-disabled variant -- with audit_utils OFF, even a member holding
  #    EVERY audit permission sees none of the surfaces.
  # ===========================================================================

  def test_module_disabled_hides_all_surfaces_even_with_all_permissions
    # Turn the module OFF for project 1 (setup enabled it). A subsequent test's
    # setup re-enables it; tests are otherwise hermetic on unique logins.
    EnabledModule.where(project_id: @project.id, name: 'audit_utils').delete_all

    log_in_with_permissions(%i[view_audit_reports use_user_autofill
                               manage_tracked_users add_issues view_issues])

    # Report + tracked-user actions are forbidden (module-scoped permissions are
    # inert when the module is disabled).
    visit reports_index_url
    assert_text NOT_AUTHORIZED_TEXT

    visit tracked_users_url
    assert_text NOT_AUTHORIZED_TEXT

    # Menu items (guarded by `if: module_enabled?`) are gone.
    visit project_overview_url
    within '#main-menu' do
      assert_no_link 'Reports'
      assert_no_link 'Manage Vendors/Volunteers'
    end

    # Autofill hook bails out on the module check before the permission check.
    visit new_issue_url
    assert_no_selector '#user-search-widget'
  end

  private

  # --- URLs -----------------------------------------------------------------

  def reports_index_url
    "/projects/#{@project.identifier}/audit_reports"
  end

  def daily_report_url
    "/projects/#{@project.identifier}/audit_reports/daily"
  end

  def weekly_report_url
    "/projects/#{@project.identifier}/audit_reports/weekly" \
      "?start_date=#{(Date.current - 7).iso8601}&end_date=#{Date.current.iso8601}"
  end

  def tracked_users_url
    "/projects/#{@project.identifier}/tracked_users"
  end

  def project_overview_url
    "/projects/#{@project.identifier}"
  end

  def new_issue_url
    "/projects/#{@project.identifier}/issues/new?issue[tracker_id]=#{@tracker.id}"
  end

  # --- Seeding --------------------------------------------------------------

  # Minimal synthetic open issue in the audit project/tracker.
  def seed_issue(subject)
    Issue.create!(project: @project, tracker_id: @tracker.id, author_id: 1,
                  status_id: 1, subject: subject)
  end
end
