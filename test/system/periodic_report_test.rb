# frozen_string_literal: true

require File.expand_path('../system_test_helper', __dir__)

# End-to-end (browser) tests for the Quarterly/Annual (periodic) audit report,
# which feeds the SFMS Quarterly Audit and the SFS Annual Audit.
#
# Like the Weekly report, the periodic report is driven by CLOSED Redmine
# issues (filtered by Target System + closed_on window) -- no ESS. These tests
# seed synthetic closed issues per target system, then drive the web view and
# CSV export through the browser.
class PeriodicReportTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers, :issues

  setup do
    @project, @tracker, @fields = setup_audit_utils_project

    # The periodic report surfaces a "BAC #" (BacNumber) column. The standard
    # field setup does not include a BAC field, so add one and register it.
    @bac_field = create_or_find_field('BAC #', 'string', [], @tracker)
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'bac_number_field_id' => @bac_field.id.to_s
    )

    log_in_as_admin
  end

  # ---------------------------------------------------------------------------
  # 4. Web view for a single target system (SFMS) renders seeded closed tickets.
  # ---------------------------------------------------------------------------
  def test_web_view_renders_seeded_sfms_tickets
    sfms = seed_closed_issue(target_system: 'Oracle / SFMS', subject: 'Yara SFMS Add',
                             user_name: 'Yara Fakeperson', user_uid: 'yfakeperson', bac: '900777')
    # An out-of-system ticket that must NOT appear in the SFMS report.
    sfs = seed_closed_issue(target_system: 'SFS', subject: 'Xander SFS Add',
                            user_name: 'Xander Nobody', user_uid: 'xnobody')

    visit periodic_url(system: 'sfms')

    assert_selector 'table.periodic-report-table'
    within 'table.periodic-report-table' do
      assert_text "##{sfms.id}"
      assert_text 'Yara SFMS Add'      # Description (subject)
      assert_text 'Yara Fakeperson'    # FullName
      assert_text 'yfakeperson'        # Userid
      assert_text '900777'             # BacNumber
      assert_text 'USRA'               # RequestType (Oracle/SFMS + Add)
      assert_no_text 'Xander Nobody'   # SFS ticket excluded from SFMS report
    end
  end

  # ---------------------------------------------------------------------------
  # 5. CSV export: assert the legacy audit-spreadsheet columns are present.
  # ---------------------------------------------------------------------------
  def test_csv_export_has_legacy_spreadsheet_columns
    sfms = seed_closed_issue(target_system: 'Oracle / SFMS', subject: 'Yara SFMS Add',
                             user_name: 'Yara Fakeperson', user_uid: 'yfakeperson', bac: '900777')

    visit periodic_url(system: 'sfms')

    # The Excel export link lives next to the CSV link.
    assert_link 'Export Excel'

    # Periodic CSV has NO metadata preamble -- the header IS the first row.
    table = downloaded_csv { click_link 'Export CSV' }

    %w[RequestType FullName Userid Office EntryDate CompletedDate BacNumber
       SenDevNumber GeneralFormInfoID Program Description].each do |col|
      assert_includes table.headers, col
    end

    row = table.find { |r| r['SenDevNumber'].to_s == sfms.id.to_s }
    assert row, "Expected a CSV row for issue ##{sfms.id}"
    assert_equal 'Yara Fakeperson', row['FullName']
    assert_equal 'yfakeperson', row['Userid']
    assert_equal '900777', row['BacNumber']
    assert_equal 'USRA', row['RequestType']
  end

  # ---------------------------------------------------------------------------
  # 6. Empty state renders cleanly (no closed SFS tickets in the window).
  # ---------------------------------------------------------------------------
  def test_empty_state_renders_cleanly
    # Seed an SFS ticket but outside the window queried below.
    seed_closed_issue(target_system: 'SFS', subject: 'Old SFS', user_name: 'Old Holder',
                      user_uid: 'oldholder', closed_on: Time.zone.parse('2001-06-15'))

    visit periodic_url(system: 'sfs', start_date: '2020-01-01', end_date: '2020-12-31')

    assert_no_selector 'table.periodic-report-table'
    assert_selector 'p.nodata', text: /No closed SFS tickets found/
  end

  private

  def periodic_url(system:, start_date: (Date.current - 7).iso8601, end_date: Date.current.iso8601)
    "/projects/#{@project.identifier}/audit_reports/periodic" \
      "?system=#{system}&start_date=#{start_date}&end_date=#{end_date}"
  end

  # Seed one CLOSED issue for a given target system, with synthetic data.
  def seed_closed_issue(target_system:, subject:, user_name:, user_uid:,
                        action: 'Add', bac: nil, office: 'Fake Office 9',
                        closed_on: 2.days.ago)
    issue = Issue.new(project: @project, tracker_id: @tracker.id, author_id: 1,
                      status_id: 5, subject: subject)
    values = {
      @fields[:user_name].id      => user_name,
      @fields[:user_uid].id       => user_uid,
      @fields[:user_location].id  => office,
      @fields[:account_action].id => action,
      @fields[:target_system].id  => target_system
    }
    values[@bac_field.id] = bac if bac
    issue.custom_field_values = values
    issue.save!
    Issue.where(id: issue.id).update_all(created_on: closed_on - 4.days,
                                         updated_on: closed_on, closed_on: closed_on)
    issue
  end
end
