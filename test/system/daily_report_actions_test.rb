# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end browser tests for the Daily Report's per-row action buttons that
# launch pre-filled account-request tickets (AccountRequestsController#new):
#
#   * the "Create New" (add) icon -> a create ticket pre-filled with the row's
#     Account Holder fields from ESS; saving creates the issue, and
#   * the "Create removal ticket" (del) icon -> a removal ticket pre-filled with
#     Target System + Account Action=Delete, plus (when the "Removal Ticket
#     Defaults" user is configured) Requested By / Authorizing Users.
#
# Both action links open in a new browser tab (target=_blank), so the tests use
# window_opened_by / within_window to drive the launched form.
#
# The daily report rows come from the synthetic statusChanges fixture; the
# per-row action links carry the row's employeeId, which the launcher looks up
# again via ESS (find_by_id -> /api/v1/redmine/employee/:id). That single-lookup
# endpoint returns { success:, employee: } (NOT the search "result" shape), so
# these tests stub it with a purpose-built body.
class DailyReportActionsTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  # Synthetic employee 900101 from the statusChanges fixture, in the single
  # -lookup response shape consumed by EssEmployeeService.find_by_id.
  EMPLOYEE_900101 = {
    employeeId: 900101, uid: nil, firstName: 'Ulric', lastName: 'Doodlewick',
    initial: 'F.', suffix: '', fullName: 'Ulric F. Doodlewick',
    email: nil, workPhone: '(555) 200-1100', active: true,
    location: {
      code: 'D21001', locationType: 'Work Location',
      respCenterHead: { active: true, code: 'PERSONNEL', shortName: 'PERSONNEL',
                        name: 'Personnel Department', affiliateCode: 'ADM' }
    }
  }.freeze

  setup do
    # attach_daily_report writes a container-less Attachment diskfile via the
    # process-global Attachment.storage_path shared with the in-process Puma
    # thread; point it at the throwaway tmp dir so the save succeeds.
    set_tmp_attachments_directory

    @project, @tracker, @field_map = setup_audit_utils_project
    stub_ess_status_changes
    stub_ess_employee_lookup_full(900101, EMPLOYEE_900101)
    log_in_as_admin
  end

  # 5. "Create ticket" button -> pre-filled new account-request form ---------
  def test_create_ticket_button_prefills_and_saves
    visit daily_project_audit_reports_path(@project)

    # The add ("Create New") icon lives in the 900101 row and opens a new tab.
    new_window = window_opened_by do
      within(find('tr', text: 'Doodlewick, Ulric F.')) { click_link 'Create New' }
    end

    within_window(new_window) do
      # Lands on the new-issue form, pre-filled from the ESS employee record.
      assert_selector 'input#issue_subject'
      assert_equal 'Doodlewick, Ulric F.',
                   find("#issue_custom_field_values_#{@field_map[:user_name].id}").value
      assert_equal '900101',
                   find("#issue_custom_field_values_#{@field_map[:user_id].id}").value
      # Account Holder Type is fixed to Employee for report-launched tickets.
      assert_equal 'Employee',
                   find("#issue_custom_field_values_#{@field_map[:user_type].id}").value

      # Saving creates the issue.
      fill_in 'issue_subject', with: 'E2E create ticket for Doodlewick'
      assert_difference -> { Issue.count }, 1 do
        click_button 'Create'
        assert_text 'E2E create ticket for Doodlewick'
      end
      assert_match %r{/issues/\d+}, current_path
      # Pre-filled Account Holder Name persisted onto the saved issue.
      assert_text 'Doodlewick, Ulric F.'
    end

    # The launch link carried the report window (from_date/to_date), so
    # AccountRequestsController#attach_daily_report should have generated the
    # daily-report CSV and attached it to the saved ticket. Verify the browser
    # -driven flow actually wires the attachment up (not just the field prefill).
    created = Issue.order(:id).last
    assert_equal 'E2E create ticket for Doodlewick', created.subject
    assert created.attachments.any? { |a| a.filename =~ /\Adaily_report_\d{8}\.csv\z/ },
           'expected the report-launched ticket to carry a daily_report_*.csv attachment ' \
           "(got: #{created.attachments.map(&:filename).inspect})"
  end

  # 6. "Remove access" button -> pre-filled removal ticket -------------------
  def test_removal_ticket_button_prefills_defaults
    # Give 900101 an active Oracle / SFMS account so the report offers a removal
    # link for that system.
    seed_active_account(user_id: '900101', target_system: 'Oracle / SFMS')

    # Configure the Requested By / Authorizing Users fields and the "Removal
    # Ticket Defaults" requester so the removal ticket auto-populates them.
    requested_by, authorizing = configure_removal_defaults_fields
    requester = configure_removal_requester

    visit daily_project_audit_reports_path(@project)

    new_window = window_opened_by do
      within(find('tr', text: 'Doodlewick, Ulric F.')) { click_link 'Create removal ticket' }
    end

    within_window(new_window) do
      assert_selector 'input#issue_subject'
      # Removal subject uses the request code (USR + I) and the display name.
      assert_equal 'USRI: Remove Oracle / SFMS account for Ulric F. Doodlewick',
                   find('#issue_subject').value
      # Target System + Account Action pre-filled for the removal.
      assert_equal 'Oracle / SFMS',
                   find("#issue_custom_field_values_#{@field_map[:target_system].id}").value
      assert_equal 'Delete',
                   find("#issue_custom_field_values_#{@field_map[:account_action].id}").value

      # Removal Ticket Defaults: Requested By (single) auto-populated...
      assert_equal requester.id.to_s,
                   find("#issue_custom_field_values_#{requested_by.id}").value
      # ...and the same user selected in Authorizing Users (multiple).
      assert_selector "#issue_custom_field_values_#{authorizing.id} option[selected][value='#{requester.id}']"
    end
  end

  private

  # Stub the ESS single-employee lookup (/api/v1/redmine/employee/:id) with a
  # { success:, employee: } body, which is what find_by_id reads (the shared
  # stub_ess_employee_lookup helper returns the search "result" shape instead).
  def stub_ess_employee_lookup_full(employee_id, employee_hash)
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/employee/#{employee_id}\b})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { success: true, employee: employee_hash }.to_json
      )
  end

  # Create a closed "Add" ticket so AccountTrackingService reports an active
  # account for the given user/system (which the daily report needs to render a
  # removal link).
  def seed_active_account(user_id:, target_system:, account_action: 'Add')
    closed_status = IssueStatus.where(is_closed: true).first
    issue = Issue.new(
      project: @project, tracker: @tracker, author: User.find(1),
      status: closed_status, priority: IssuePriority.first,
      subject: "Grant #{target_system} for #{user_id}"
    )
    issue.custom_field_values = {
      @field_map[:user_id].id => user_id,
      @field_map[:account_action].id => account_action,
      @field_map[:target_system].id => target_system
    }
    issue.save!
    # Ensure the closed_on the tracking query filters on is set.
    issue.update_column(:closed_on, Time.current) if issue.closed_on.nil?
    issue
  end

  # Create/attach the Requested By (single user) and Authorizing Users (multiple
  # user) custom fields and register their IDs in plugin settings.
  def configure_removal_defaults_fields
    requested_by = find_or_create_user_field('Requested By', multiple: false)
    authorizing  = find_or_create_user_field('Authorizing User(s)', multiple: true)

    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'requested_by_field_id' => requested_by.id.to_s,
      'authorizing_users_field_id' => authorizing.id.to_s
    )
    [requested_by, authorizing]
  end

  def find_or_create_user_field(name, multiple:)
    field = IssueCustomField.find_by(name: name) ||
            IssueCustomField.create!(name: name, field_format: 'user',
                                     multiple: multiple, is_for_all: true)
    field.update!(is_for_all: true) unless field.is_for_all
    @tracker.custom_fields << field unless @tracker.custom_fields.include?(field)
    field
  end

  # Create a project-member user and set it as the "Removal Ticket Defaults"
  # requester. Membership makes the user an available option in the user fields.
  def configure_removal_requester
    requester = User.generate!(login: "removal_req_#{SecureRandom.hex(4)}",
                               firstname: 'Rex', lastname: 'Requester')
    requester.update!(must_change_passwd: false)
    role = Role.generate!(name: "Removal Req #{SecureRandom.hex(4)}", permissions: [:add_issues])
    Member.create!(principal: requester, project: @project, roles: [role])

    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'removal_ticket_requester_user_id' => requester.id.to_s
    )
    requester
  end
end
