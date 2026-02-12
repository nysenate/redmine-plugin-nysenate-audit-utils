# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class AutofillHooksTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :enabled_modules, :roles, :members, :member_roles,
           :trackers, :issue_statuses, :custom_fields

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @admin = User.find(1)

    # Create Account Request tracker
    @tracker = Tracker.find_by(name: 'Bug') || Tracker.first

    # Setup standard BACHelp fields for the tracker
    @fields = setup_standard_bachelp_fields(@tracker)

    # Create an issue with the tracker
    @issue = Issue.new(
      project: @project,
      tracker: @tracker,
      subject: 'Test Issue',
      author: @admin,
      status: IssueStatus.first
    )
    @issue.save!

    # Create a mock controller with render_to_string capability
    @controller = MockController.new

    # Access the hook instance (hooks use singleton pattern)
    @hook = NysenateAuditUtils::Autofill::Hooks.instance

    # Default context for hook calls
    @context = {
      issue: @issue,
      controller: @controller
    }

    User.current = @admin
  end

  def teardown
    clear_audit_configuration
    User.current = nil
  end

  # Test 1: Widget should NOT be displayed when Employee Autofill module is NOT enabled for the project
  def test_widget_not_shown_when_autofill_module_disabled
    # Ensure the Employee Autofill module is NOT enabled for the project
    @project.enabled_modules.where(name: 'audit_utils_employee_autofill').destroy_all
    @project.reload

    # User has permission globally
    User.current = @admin

    result = @hook.view_issues_form_details_bottom(@context)

    # Widget should NOT be shown when module is disabled
    assert_equal '', result, "Widget should not be shown when Employee Autofill module is disabled for the project"
  end

  # Test 2: Widget should be displayed when Employee Autofill module IS enabled
  def test_widget_shown_when_autofill_module_enabled
    # Enable the Employee Autofill module for the project
    @project.enable_module!(:audit_utils_employee_autofill)

    # User has permission
    User.current = @admin
    @admin.stubs(:allowed_to?).with(:use_employee_autofill, @project).returns(true)

    result = @hook.view_issues_form_details_bottom(@context)

    assert_not_equal '', result
    assert_match /employee-search-widget/, result
  end

  # Test 3: Widget should NOT be displayed when user does NOT have use_employee_autofill permission for the project
  def test_widget_not_shown_when_user_lacks_permission
    # Enable the module
    @project.enable_module!(:audit_utils_employee_autofill)

    # Remove the user's permission for this project
    # User 2 is a member with role 1 (Manager) - remove that permission
    role = Role.find(1)
    role.remove_permission!(:use_employee_autofill) if role.permissions.include?(:use_employee_autofill)

    User.current = @user

    result = @hook.view_issues_form_details_bottom(@context)

    # Widget should NOT be shown when user lacks permission
    assert_equal '', result, "Widget should not be shown when user lacks use_employee_autofill permission"
  end

  # Test 4: Widget should be displayed when user HAS use_employee_autofill permission
  def test_widget_shown_when_user_has_permission
    # Enable the module
    @project.enable_module!(:audit_utils_employee_autofill)

    # Reload issue to pick up fresh project state with updated allowed_permissions cache
    @issue.reload

    # Ensure user has permission
    role = Role.find(1)
    role.add_permission!(:use_employee_autofill)

    User.current = @user

    result = @hook.view_issues_form_details_bottom(@context)

    assert_not_equal '', result
    assert_match /employee-search-widget/, result
  end

  # Test 5: Widget should NOT be displayed when tracker has no employee fields
  def test_widget_not_shown_when_tracker_has_no_employee_fields
    # Create a tracker without employee fields
    tracker_no_fields = Tracker.create!(
      name: 'No Fields Tracker',
      default_status: IssueStatus.first
    )

    # Enable the tracker for the project
    @project.trackers << tracker_no_fields unless @project.trackers.include?(tracker_no_fields)

    issue_no_fields = Issue.new(
      project: @project,
      tracker: tracker_no_fields,
      subject: 'Test Issue No Fields',
      author: @admin,
      status: IssueStatus.first
    )
    issue_no_fields.save!

    context = {
      issue: issue_no_fields,
      controller: @controller
    }

    # Enable module and grant permission
    @project.enable_module!(:audit_utils_employee_autofill)
    User.current = @admin

    result = @hook.view_issues_form_details_bottom(context)

    assert_equal '', result
  end

  # Test 6: Combined test - all conditions must be met
  def test_widget_only_shown_when_all_conditions_met
    # Enable module
    @project.enable_module!(:audit_utils_employee_autofill)

    # Reload issue to pick up fresh project state with updated allowed_permissions cache
    @issue.reload

    # Grant permission
    User.current = @admin

    # Has employee fields (already set up in setup)

    result = @hook.view_issues_form_details_bottom(@context)

    assert_not_equal '', result
    assert_match /employee-search-widget/, result
  end

  # Test 7: Widget not shown on issue without tracker
  def test_widget_not_shown_when_issue_has_no_tracker
    issue_no_tracker = Issue.new(
      project: @project,
      subject: 'Test Issue No Tracker',
      author: @admin,
      status: IssueStatus.first
    )
    # Don't set tracker

    context = {
      issue: issue_no_tracker,
      controller: @controller
    }

    result = @hook.view_issues_form_details_bottom(context)

    assert_equal '', result
  end

  # Test 8: Widget not shown when issue is nil
  def test_widget_not_shown_when_issue_is_nil
    context = { issue: nil, controller: @controller }

    result = @hook.view_issues_form_details_bottom(context)

    assert_equal '', result
  end

  # Mock controller class for testing
  class MockController
    def render_to_string(options)
      # Return a mock HTML widget
      '<div id="employee-search-widget" class="employee-search-widget"></div>'
    end
  end
end
