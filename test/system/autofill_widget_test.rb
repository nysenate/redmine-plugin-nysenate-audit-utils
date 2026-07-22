# frozen_string_literal: true

require File.expand_path('../system_test_helper', __dir__)

# End-to-end tests for the Account Holder search/autofill widget behaviour that
# the smoke test in user_autofill_test.rb does NOT cover:
#
#   1. Clicking a search result actually populates the mapped Account Holder
#      custom-field inputs on the new-issue form.
#   2. The Employee/Vendor/Volunteer type selector routes the search to the
#      right data source (ESS for Employee, local tracked_users for the rest).
#   3. The widget is suppressed when its prerequisites (module enabled + a
#      configured autofill field on the tracker) are not met.
#
# See system_test_helper.rb for the driver/WebMock/ESS-stub story and the
# available helpers. All seeded identity data is synthetic (ESS fixture
# employeeIds 900001+, tracked_users fixture "Fixture Vendor/Volunteer …").
class AutofillWidgetTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :issue_statuses, :enumerations,
           :projects_trackers

  # --------------------------------------------------------------------------
  # 1. Selecting a result fills the mapped Account Holder custom fields.
  # --------------------------------------------------------------------------
  def test_selecting_employee_result_populates_mapped_custom_fields
    project, tracker, fields = setup_audit_utils_project
    stub_ess_employee_search
    log_in_as_admin

    visit new_issue_path_for(project, tracker)
    assert_selector '#user-search-widget'

    # The stub returns the whole employee fixture regardless of query; pick the
    # record with a populated email/uid so every mapped field is exercised.
    # employeeId 900002 => Boris B. Mockridge Jr. (formatted surname-first).
    fill_in 'user-search-input', with: 'Mock'
    within '#user-results-list' do
      find('li', text: 'Mockridge').click
    end

    # Text custom fields get their value from the selected result. The first
    # assert_field auto-waits for the (synchronous) JS autofill to complete.
    assert_field field_input_id(fields, :user_name),  with: 'Mockridge, Boris B., Jr.'
    assert_field field_input_id(fields, :user_email), with: 'bmockrid@nysenate.gov'
    assert_field field_input_id(fields, :user_id),    with: '900002'
    assert_field field_input_id(fields, :user_uid),   with: 'bmockrid'
    assert_field field_input_id(fields, :user_location), with: 'BRIGHTWATER'

    # The Account Holder Type is a list field: the widget selects the option
    # matching the result's type ("Employee").
    type_select = find("##{field_input_id(fields, :user_type)}")
    assert_equal 'Employee', type_select.value
  end

  # --------------------------------------------------------------------------
  # 2. Type selector routes to the correct data source.
  # --------------------------------------------------------------------------
  def test_type_switch_routes_between_ess_and_tracked_users
    project, tracker, _fields = setup_audit_utils_project
    stub_ess_employee_search
    seed_tracked_users
    log_in_as_admin

    visit new_issue_path_for(project, tracker)

    # Employee (default) -> ESS: "Testwell" comes from the ESS fixture and is
    # NOT present in the tracked_users table.
    fill_in 'user-search-input', with: 'Test'
    within '#user-results-list' do
      assert_text 'Testwell'
    end

    # Switch to Vendor -> local tracked_users (no ESS stub for this path). The
    # radio's change handler clears the input, so type a fresh vendor query.
    find('input[name="user-type"][value="Vendor"]').click
    fill_in 'user-search-input', with: 'Vendor One'
    within '#user-results-list' do
      assert_text 'Fixture Vendor One' # from tracked_users.yml
      assert_no_text 'Testwell'        # ESS result is gone -> different source
    end

    # Switch to Volunteer -> also local tracked_users, but only Volunteer rows.
    find('input[name="user-type"][value="Volunteer"]').click
    fill_in 'user-search-input', with: 'Volunteer One'
    within '#user-results-list' do
      assert_text 'Fixture Volunteer One'
      assert_no_text 'Fixture Vendor One'
    end
  end

  # --------------------------------------------------------------------------
  # 3a. Widget hidden when the audit_utils module is disabled for the project.
  # --------------------------------------------------------------------------
  def test_widget_absent_when_module_disabled
    project, tracker, _fields = setup_audit_utils_project(enable_module: false)
    # The shared system DB persists module state across tests, so disable
    # explicitly rather than relying on a clean slate.
    project.enabled_modules.where(name: 'audit_utils').destroy_all
    project.reload
    log_in_as_admin

    visit new_issue_path_for(project, tracker)

    # The new-issue form still renders (issues are core), but the widget must not.
    assert_selector '#issue_subject'
    assert_no_selector '#user-search-widget'
  end

  # --------------------------------------------------------------------------
  # 3b. Widget hidden when no autofill field is configured for the tracker.
  # --------------------------------------------------------------------------
  def test_widget_absent_when_no_autofill_field_configured
    # Module enabled + ESS configured, but no Account Holder fields mapped
    # (settings are cleared per-test, so autofill_field_ids is empty).
    project, tracker, _fields = setup_audit_utils_project(fields: false)
    log_in_as_admin

    visit new_issue_path_for(project, tracker)

    assert_selector '#issue_subject'
    assert_no_selector '#user-search-widget'
  end

  private

  # Seed synthetic Vendor/Volunteer rows for the local (tracked_users) search
  # path. Done inline rather than via the tracked_users.yml fixture because that
  # fixture uses the removed `to_s(:db)` helper and won't load under Rails 7.2.
  # Idempotent so a retry on the shared (non-transactional) system DB is safe.
  def seed_tracked_users
    [
      { user_type: 'Vendor',    user_id: 900_501, name: 'Fixture Vendor One',    email: 'vendor1@example.test',    status: 'Active' },
      { user_type: 'Volunteer', user_id: 900_601, name: 'Fixture Volunteer One', email: 'volunteer1@example.test', status: 'Active' }
    ].each do |attrs|
      TrackedUser.where(user_id: attrs[:user_id]).destroy_all
      TrackedUser.create!(attrs)
    end
  end

  # New-issue form URL pre-selecting the audit tracker (so its custom fields and
  # the widget render).
  def new_issue_path_for(project, tracker)
    "/projects/#{project.identifier}/issues/new?issue[tracker_id]=#{tracker.id}"
  end

  # DOM id Redmine gives a custom-field value input on the issue form, matching
  # the field_mappings the widget consumes (issue_custom_field_values_<cf_id>).
  def field_input_id(fields, key)
    "issue_custom_field_values_#{fields[key].id}"
  end
end
