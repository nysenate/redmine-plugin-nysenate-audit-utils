# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# End-to-end (browser) tests for the Vendor/Volunteer (tracked users)
# management UI.
#
# The CRUD UI is served by TrackedUsersController and is PROJECT-SCOPED: it
# lives under /projects/:project_id/tracked_users and is reached from the
# project menu item "Manage Vendors/Volunteers" (registered in init.rb).
# Access is gated by the `manage_tracked_users` permission AND the
# `audit_utils` module being enabled on the project. The README's mention of
# an admin-level menu does not correspond to a separate route -- this is the
# real UI.
#
# ---------------------------------------------------------------------------
# ID SCHEME NOTE: despite the task brief's mention of "V1, V2...", the real
# auto-generated ID scheme (see TrackedUser.next_tracked_user_id and the form
# hint "Auto-generated numeric ID (e.g., 500001, 500002)") is NUMERIC with a
# 500_000 offset. These tests assert the real numeric scheme.
# ---------------------------------------------------------------------------
#
# TEST DATA POLICY: only obviously-synthetic vendor/volunteer data.
class TrackedUsersManagementTest < AuditUtilsSystemTestCase
  fixtures :users, :projects, :roles, :members, :member_roles,
           :trackers, :enabled_modules, :enumerations

  setup do
    # Maps the standard fields, points ESS at the fake host, and enables the
    # audit_utils module on project 1 (required for manage_tracked_users to
    # take effect). We don't need ESS or the fields here, but reusing the
    # one-call helper keeps setup consistent and enables the module.
    @project, @tracker, @fields = setup_audit_utils_project

    # Deterministic clean slate: the tracked_users table is shared across the
    # process, so clear it so the index starts empty and the auto-generated
    # IDs begin predictably at the 500_000 offset + 1.
    TrackedUser.delete_all

    log_in_as_admin
  end

  teardown do
    TrackedUser.delete_all
  end

  # ---------------------------------------------------------------------------
  # 1. Full CRUD: create, verify auto-ID + increment, edit, delete.
  # ---------------------------------------------------------------------------
  def test_full_crud_lifecycle
    # --- Empty state -------------------------------------------------------
    visit tracked_users_url
    assert_selector 'p.nodata', text: 'No Vendors/Volunteers found'

    # --- Create first vendor ----------------------------------------------
    id1 = create_tracked_user(type: 'Vendor', name: 'Synthetic Vendor Alpha',
                              email: 'alpha@vendor.test')

    # Back on the index: the new vendor shows with its auto-generated numeric
    # ID and details.
    assert_current_index
    row = find('table.list.tracked-users tr', text: 'Synthetic Vendor Alpha')
    within(row) do
      assert_text id1.to_s
      assert_text 'Vendor'
      assert_text 'alpha@vendor.test'
      assert_text 'Active'
    end

    # --- Create second vendor: ID must increment --------------------------
    id2 = create_tracked_user(type: 'Volunteer', name: 'Synthetic Volunteer Beta',
                              email: 'beta@vol.test')
    assert_equal id1 + 1, id2,
                 "Auto-generated ID should increment (#{id1} -> expected #{id1 + 1}, got #{id2})"

    within find('table.list.tracked-users tr', text: 'Synthetic Volunteer Beta') do
      assert_text id2.to_s
      assert_text 'Volunteer'
    end

    # --- Edit the first vendor --------------------------------------------
    within find('table.list.tracked-users tr', text: 'Synthetic Vendor Alpha') do
      click_link 'Edit'
    end
    assert_selector 'h2', text: 'Edit Vendor/Volunteer'
    # ID stays fixed and read-only across an edit.
    assert_equal id1.to_s, find('#tracked_user_user_id').value
    fill_in 'tracked_user_name', with: 'Synthetic Vendor Alpha Renamed'
    select 'Inactive', from: 'tracked_user_status'
    click_button 'Save Vendor/Volunteer'

    assert_current_index
    assert_text 'Synthetic Vendor Alpha Renamed'
    within find('table.list.tracked-users tr', text: 'Synthetic Vendor Alpha Renamed') do
      assert_text 'Inactive'
    end
    # Persisted server-side, not just visually. (The name changed in place --
    # the record keeps the same auto-generated ID, and no stale row survives.)
    assert_equal 'Synthetic Vendor Alpha Renamed', TrackedUser.find_by(user_id: id1).name
    assert_nil TrackedUser.find_by(name: 'Synthetic Vendor Alpha'),
               'Pre-rename name should no longer exist as a record'

    # --- Delete the second vendor -----------------------------------------
    within find('table.list.tracked-users tr', text: 'Synthetic Volunteer Beta') do
      accept_confirm { click_link 'Delete' }
    end

    assert_current_index
    assert_no_text 'Synthetic Volunteer Beta'
    assert_nil TrackedUser.find_by(user_id: id2), 'Deleted record should be gone from the DB'
    # The renamed vendor is still present (only the second was deleted).
    assert_text 'Synthetic Vendor Alpha Renamed'
  end

  # ---------------------------------------------------------------------------
  # 2. Validation: an invalid submission re-renders the form with errors and
  #    creates no record.
  # ---------------------------------------------------------------------------
  def test_invalid_submission_shows_errors_and_creates_nothing
    visit tracked_users_url
    click_link 'New Vendor/Volunteer'

    # The Name field carries an HTML5 `required` attribute, so a truly empty
    # value would be blocked by the browser before POSTing. Submit whitespace
    # instead: it satisfies the browser's non-empty check but fails Rails'
    # presence validation (blank?), exercising the server-side error path.
    fill_in 'tracked_user_name', with: '   '

    assert_no_difference 'TrackedUser.count' do
      click_button 'Create Vendor/Volunteer'
      # Wait for the re-rendered form (error box) before the assertion below.
      assert_selector 'div#errorExplanation'
    end

    # Still on the new/create form (no redirect to the index).
    assert_selector 'form'
    assert_no_selector 'table.list.tracked-users'
  end

  private

  def tracked_users_url
    "/projects/#{@project.identifier}/tracked_users"
  end

  # Assert the browser is back on the tracked-users index (post-redirect).
  def assert_current_index
    assert_selector 'h2', text: 'Manage Vendors/Volunteers'
    assert_selector 'table.list.tracked-users'
  end

  # Drive the "New Vendor/Volunteer" form through the browser and submit it.
  # Returns the auto-generated numeric ID (as an Integer) that the form
  # pre-filled into the read-only ID field.
  def create_tracked_user(type:, name:, email: nil)
    visit tracked_users_url
    click_link 'New Vendor/Volunteer'
    assert_selector 'h2', text: 'New Vendor/Volunteer'

    generated_id = find('#tracked_user_user_id').value.to_i
    select type, from: 'tracked_user_user_type'
    fill_in 'tracked_user_name', with: name
    fill_in 'tracked_user_email', with: email if email
    click_button 'Create Vendor/Volunteer'

    generated_id
  end
end
