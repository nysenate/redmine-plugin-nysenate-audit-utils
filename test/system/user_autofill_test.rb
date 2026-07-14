# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end smoke test for the Account Holder search/autofill widget.
#
# Primary purpose of THIS test: prove the plumbing works --
#   browser types into the widget
#     -> JS calls /user_search/search
#       -> UserService -> EmployeeDataSource -> EssEmployeeService
#         -> EssApiClient (Net::HTTP) -> WebMock intercepts in-process
#           -> canned ESS fixture rendered back into the results list.
#
# If the results list shows a name from employee_search_response.json, the
# `allow_localhost` + in-process WebMock interception story is confirmed and
# the rest of the system-test suite can be built on this base.
class UserAutofillTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  setup do
    @project = Project.find(1)
    @tracker = Tracker.find(1)

    # Create the Account Holder custom fields, attach them to the tracker, and
    # register their IDs in plugin settings (widget only renders when the
    # tracker has at least one configured autofill field).
    setup_standard_bachelp_fields(@tracker)

    # Merge ESS host/key in AFTER field setup (it replaces the settings hash).
    configure_ess!

    # Enable the plugin module so the hook + controller permit the widget.
    @project.enable_module!(:audit_utils)

    # Canned ESS response for the search the browser will trigger.
    stub_ess_employee_search

    # Admin is allowed_to? everything, so no role/membership wiring needed.
    log_user('admin', 'admin')
  end

  def test_employee_search_populates_results_from_ess
    visit "/projects/#{@project.identifier}/issues/new?issue[tracker_id]=#{@tracker.id}"

    # Widget renders on the new-issue form.
    assert_selector '#user-search-widget'

    # Typing triggers a debounced fetch to /user_search/search.
    fill_in 'user-search-input', with: 'test'

    # Results come back from the stubbed ESS fixture (employeeId 900001 =
    # "Ada A. Testwell"). Capybara auto-waits for the AJAX + DOM update.
    within '#user-results-list' do
      assert_text 'Testwell'
    end
  end
end
