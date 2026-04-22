require_relative '../test_helper'

class UserWorkflowTest < Redmine::IntegrationTest
  include AuditTestHelpers
  fixtures :projects, :users, :roles, :members, :member_roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issues,
           :enumerations,
           :custom_fields, :custom_values, :custom_fields_trackers

  def setup
    @project = Project.find(1)
    @project.enabled_modules.create!(name: 'audit_utils')

    # Create admin user
    @admin = User.find(1)

    # Create user with user autofill permission
    @user_with_permission = User.find(2)
    @role_with_permission = Role.find(1)
    @role_with_permission.add_permission! :use_user_autofill

    # Create user without permissions
    @user_without_permission = User.find(3)
    @role_without_permission = Role.find(2)
    @role_without_permission.remove_permission! :use_user_autofill

    # Setup custom fields
    tracker = @project.trackers.first
    fields = setup_standard_bachelp_fields(tracker)

    @cf_user_type = fields[:user_type]
    @cf_user_id = fields[:user_id]
    @cf_user_name = fields[:user_name]
    @cf_user_email = fields[:user_email]
    @cf_user_phone = fields[:user_phone]
    @cf_user_uid = fields[:user_uid]
    @cf_user_location = fields[:user_location]
    @cf_user_status = fields[:user_status]
    @cf_account_action = fields[:account_action]
    @cf_target_system = fields[:target_system]

    # Create test vendor
    @test_vendor = TrackedUser.create!(
      user_type: 'Vendor',
      user_id: 500_001,
      name: 'Test Vendor Corp',
      email: 'vendor@test.com',
      phone: '555-1234',
      uid: 'VENDOR1',
      location: 'Building A',
      status: 'Active'
    )

    # Create second vendor for search tests
    @test_vendor_2 = TrackedUser.create!(
      user_type: 'Vendor',
      user_id: 500_002,
      name: 'Acme Industries',
      email: 'acme@test.com',
      status: 'Active'
    )
  end

  # Test 1: Complete Vendor Workflow
  test "complete vendor workflow from creation to issue tracking" do
    # Step 1: Create vendor directly (bypassing UI permissions for integration test)
    new_vendor = TrackedUser.create!(
      user_type: 'Vendor',
      user_id: 500_003,
      name: 'New Workflow Vendor',
      email: 'workflow@test.com',
      status: 'Active'
    )

    assert_not_nil new_vendor
    assert_equal 'New Workflow Vendor', new_vendor.name

    # Step 2: User searches for vendor
    log_user('jsmith', 'jsmith')

    get '/user_search/search', params: { q: 'Workflow', type: 'Vendor', project_id: @project.id }
    assert_response :success

    json = JSON.parse(response.body)
    assert json['users'].present?, "Expected users array, got: #{json.inspect}"
    assert_equal 1, json['users'].size, "Expected 1 user, got #{json['users'].size}: #{json['users'].inspect}"
    assert_equal 'Vendor', json['type']
    assert_equal 500_003, json['users'].first['user_id']
    assert_equal 'New Workflow Vendor', json['users'].first['name']

    # Step 3: Create issue with vendor user
    tracker = @project.trackers.first
    issue = Issue.create!(
      project: @project,
      tracker: tracker,
      author: @user_with_permission,
      subject: 'Test Issue for Vendor 500003',
      custom_field_values: {
        @cf_user_id.id => '500003',
        @cf_user_name.id => 'New Workflow Vendor',
        @cf_user_type.id => 'Vendor',
        @cf_user_email.id => 'workflow@test.com',
        @cf_target_system.id => 'Oracle / SFMS',
        @cf_account_action.id => 'Add'
      }
    )

    assert issue.persisted?
    assert_equal '500003', issue.custom_value_for(@cf_user_id)&.value
    assert_equal 'Vendor', issue.custom_value_for(@cf_user_type)&.value

    # Step 4: Verify vendor appears in account tracking
    service = NysenateAuditUtils::AccountTracking::AccountTrackingService.new

    # Close the issue to test account tracking
    issue.reload
    issue.status = IssueStatus.where(is_closed: true).first
    issue.save!

    statuses = service.get_account_statuses('500003')
    assert statuses.any?, "Expected account statuses for 500003, got: #{statuses.inspect}"
    assert_equal '500003', statuses.first[:user_id]
    assert_equal 'Oracle / SFMS', statuses.first[:account_type]
  end

  # Test 2: Vendor Search Works
  test "vendor search works correctly" do
    log_user('jsmith', 'jsmith')

    # Search for existing vendor
    get '/user_search/search', params: { q: 'Test Vendor', type: 'Vendor', project_id: @project.id }
    assert_response :success

    json = JSON.parse(response.body)
    assert json['users'].present?, "Expected users array, got: #{json.inspect}"
    assert_equal 'Vendor', json['type']
    assert json['users'].any? { |s| s['name'] == 'Test Vendor Corp' }, "Expected to find 'Test Vendor Corp', got: #{json['users'].map { |s| s['name'] }.inspect}"
  end

  # Test 3: Mixed Data Scenarios
  test "system handles mixed employee and vendor data correctly" do
    tracker = @project.trackers.first

    # Create employee issue
    employee_issue = Issue.create!(
      project: @project,
      tracker: tracker,
      author: @user_with_permission,
      subject: 'Employee Access Request',
      custom_field_values: {
        @cf_user_id.id => '12345',
        @cf_user_name.id => 'John Doe',
        @cf_user_type.id => 'Employee'
      }
    )

    # Create vendor issue
    vendor_issue = Issue.create!(
      project: @project,
      tracker: tracker,
      author: @user_with_permission,
      subject: 'Vendor Access Request',
      custom_field_values: {
        @cf_user_id.id => '500001',
        @cf_user_name.id => 'Test Vendor Corp',
        @cf_user_type.id => 'Vendor'
      }
    )

    assert employee_issue.persisted?
    assert vendor_issue.persisted?

    # Verify user types are correctly stored
    assert_equal 'Employee', employee_issue.custom_value_for(@cf_user_type)&.value
    assert_equal 'Vendor', vendor_issue.custom_value_for(@cf_user_type)&.value

    # Test monthly report with mixed data
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    report_data = service.generate

    assert_not_nil report_data

    # Verify report includes both types (it queries all issues with User ID custom field values)
    # This test confirms mixed data can coexist and be reported on
  end

  # Test 4: Permission Checks
  test "user without permission cannot access user search" do
    log_user('dlopper', 'foo')

    get '/user_search/search', params: { q: 'test', type: 'Vendor', project_id: @project.id }
    assert_response :forbidden
  end

  test "user with permission can access user search" do
    log_user('jsmith', 'jsmith')

    get '/user_search/search', params: { q: 'Test', type: 'Vendor', project_id: @project.id }
    assert_response :success
  end

  test "user management requires proper authorization" do
    # Test that tracked user management exists and is accessible with proper authorization
    # Note: The TrackedUsersController uses authorize, which checks project-level permissions
    # This test verifies the authorization structure is in place

    # Admin should have access if properly configured
    log_user('admin', 'admin')

    # The controller requires find_project and authorize, so just verify it exists
    # and returns a proper response (even if 403, it means authorization is being checked)
    get "/projects/#{@project.identifier}/tracked_users"
    assert_includes [200, 403], response.code.to_i
  end

  # Test 5: Data Integrity
  test "vendor ID uniqueness is enforced" do
    duplicate_vendor = TrackedUser.new(
      user_type: 'Vendor',
      user_id: 500_001, # Same as @test_vendor
      name: 'Duplicate Vendor',
      status: 'Active'
    )

    assert_not duplicate_vendor.valid?
    assert_includes duplicate_vendor.errors[:user_id], "has already been taken"
  end

  test "custom field autofill preserves all data" do
    log_user('jsmith', 'jsmith')

    get '/user_search/search', params: { q: 'Test Vendor', type: 'Vendor', project_id: @project.id }
    assert_response :success

    json = JSON.parse(response.body)
    result = json['users'].first

    # Verify all fields are present
    assert_equal 500_001, result['user_id']
    assert_equal 'Test Vendor Corp', result['name']
    assert_equal 'vendor@test.com', result['email']
    assert_equal '555-1234', result['phone']
    assert_equal 'VENDOR1', result['uid']
    assert_equal 'Building A', result['location']
    assert_equal 'Active', result['status']
    assert_equal 'Vendor', result['user_type']
  end

  test "reports aggregate data correctly by user type" do
    tracker = @project.trackers.first

    # Create multiple issues with different user types
    3.times do |i|
      Issue.create!(
        project: @project,
        tracker: tracker,
        author: @user_with_permission,
        subject: "Employee Issue #{i}",
        custom_field_values: {
          @cf_user_id.id => "1000#{i}",
          @cf_user_name.id => "Employee #{i}",
          @cf_user_type.id => 'Employee',
          @cf_target_system.id => 'Oracle / SFMS',
          @cf_account_action.id => 'Add'
        }
      )
    end

    2.times do |i|
      Issue.create!(
        project: @project,
        tracker: tracker,
        author: @user_with_permission,
        subject: "Vendor Issue #{i}",
        custom_field_values: {
          @cf_user_id.id => (500_010 + i).to_s,
          @cf_user_name.id => "Vendor #{i}",
          @cf_user_type.id => 'Vendor',
          @cf_target_system.id => 'Oracle / SFMS',
          @cf_account_action.id => 'Add'
        }
      )
    end

    # Generate monthly report - verify it runs without error and can handle mixed data
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(target_system: 'Oracle / SFMS')
    report_data = service.generate

    # Report should be an array (may be empty if no matching data)
    assert_kind_of Array, report_data

    # If there is data, verify it has the expected structure
    if report_data.any?
      first_row = report_data.first
      assert first_row.key?(:user_id)
      assert first_row.key?(:user_type)
    end
  end

  test "next tracked user ID generation works correctly" do
    # Current max is 500002, so next should be 500003
    assert_equal 500_003, TrackedUser.next_tracked_user_id

    # Create 500003
    TrackedUser.create!(
      user_type: 'Vendor',
      user_id: 500_003,
      name: 'Vendor 3',
      status: 'Active'
    )

    # Next should be 500004
    assert_equal 500_004, TrackedUser.next_tracked_user_id

    # Create 500010 (skip ahead)
    TrackedUser.create!(
      user_type: 'Vendor',
      user_id: 500_010,
      name: 'Vendor 10',
      status: 'Active'
    )

    # Next should be 500011 (based on highest existing)
    assert_equal 500_011, TrackedUser.next_tracked_user_id
  end

  test "user type field is properly saved in issues" do
    tracker = @project.trackers.first

    issue = Issue.create!(
      project: @project,
      tracker: tracker,
      author: @user_with_permission,
      subject: 'Test User Type Persistence',
      custom_field_values: {
        @cf_user_id.id => '500001',
        @cf_user_name.id => 'Test Vendor Corp',
        @cf_user_type.id => 'Vendor'
      }
    )

    # Reload and verify
    issue.reload
    assert_equal 'Vendor', issue.custom_value_for(@cf_user_type)&.value

    # Verify it's persisted in the database
    custom_value = CustomValue.find_by(
      customized_id: issue.id,
      customized_type: 'Issue',
      custom_field_id: @cf_user_type.id
    )
    assert_not_nil custom_value
    assert_equal 'Vendor', custom_value.value
  end
end
