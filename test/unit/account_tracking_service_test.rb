# frozen_string_literal: true

require_relative '../test_helper'

module NysenateAuditUtils::AccountTracking
  class AccountTrackingServiceTest < ActiveSupport::TestCase
    fixtures :projects, :users, :roles, :members, :member_roles,
             :issues, :issue_statuses, :trackers,
             :enumerations, :custom_fields, :custom_values

    def setup
      @project = Project.find(1)
      @tracker = Tracker.find(1)

      # Use helper to setup standard fields
      @fields = setup_standard_bachelp_fields
      @employee_id_field = @fields[:employee_id]
      @account_action_field = @fields[:account_action]
      @target_system_field = @fields[:target_system]

      # Get closed and open status
      @closed_status = IssueStatus.where(is_closed: true).first
      @open_status = IssueStatus.where(is_closed: false).first

      @service = AccountTrackingService.new
    end

    def teardown
      clear_audit_configuration
    end

    test 'returns empty array for employee with no issues' do
      result = @service.get_account_statuses('99999')
      assert_equal [], result
    end

    test 'returns empty array for blank employee ID' do
      assert_equal [], @service.get_account_statuses(nil)
      assert_equal [], @service.get_account_statuses('')
    end

    test 'raises error if required custom fields not configured' do
      # Use helper to clear configuration
      clear_audit_configuration

      error = assert_raises(RuntimeError) do
        @service.get_account_statuses('12345')
      end
      assert_match /Required custom fields not found/, error.message
    end

    test 'returns active status for employee with Add action' do
      issue = create_closed_issue('12345', 'Oracle / SFMS', 'Add', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'Oracle / SFMS', result[0][:account_type]
      assert_equal 'active', result[0][:status]
      assert_equal issue.id, result[0][:issue_id]
      assert_equal 'Add', result[0][:account_action]
      assert_equal 'USRA', result[0][:request_code]
      assert_not_nil result[0][:closed_on]
    end

    test 'returns inactive status for employee with Delete action' do
      issue = create_closed_issue('12345', 'AIX', 'Delete', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'AIX', result[0][:account_type]
      assert_equal 'inactive', result[0][:status]
      assert_equal issue.id, result[0][:issue_id]
      assert_equal 'Delete', result[0][:account_action]
      assert_equal 'AIXI', result[0][:request_code]
    end

    test 'returns active status for all Update actions' do
      update_actions = ['Update Account & Privileges', 'Update Privileges Only', 'Update Account Only']

      update_actions.each_with_index do |action, index|
        employee_id = "emp_#{index}"
        issue = create_closed_issue(employee_id, 'SFS', action, 1.day.ago)

        result = @service.get_account_statuses(employee_id)

        assert_equal 1, result.length
        assert_equal 'active', result[0][:status], "Expected active status for action: #{action}"
        assert_equal action, result[0][:account_action]
      end
    end

    test 'returns multiple account types for employee with multiple systems' do
      create_closed_issue('12345', 'Oracle / SFMS', 'Add', 3.days.ago)
      create_closed_issue('12345', 'AIX', 'Add', 2.days.ago)
      create_closed_issue('12345', 'SFS', 'Delete', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 3, result.length

      # Results should be sorted by account_type
      assert_equal 'AIX', result[0][:account_type]
      assert_equal 'active', result[0][:status]

      assert_equal 'Oracle / SFMS', result[1][:account_type]
      assert_equal 'active', result[1][:status]

      assert_equal 'SFS', result[2][:account_type]
      assert_equal 'inactive', result[2][:status]
    end

    test 'uses most recent closed issue when multiple issues exist for same account type' do
      # Old issue: Add
      old_issue = create_closed_issue('12345', 'Oracle / SFMS', 'Add', 5.days.ago)
      # Recent issue: Delete (should be used)
      # Use a clearly different timestamp to ensure ordering
      recent_issue = create_closed_issue('12345', 'Oracle / SFMS', 'Delete', 1.hour.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'Oracle / SFMS', result[0][:account_type]
      assert_equal 'inactive', result[0][:status]
      assert_equal recent_issue.id, result[0][:issue_id]
      assert_equal 'Delete', result[0][:account_action]
    end

    test 'ignores open issues when determining status' do
      # Create open issue with Add
      create_open_issue('12345', 'Oracle / SFMS', 'Add')
      # Create closed issue with Delete (should be used)
      closed_issue = create_closed_issue('12345', 'Oracle / SFMS', 'Delete', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'inactive', result[0][:status]
      assert_equal closed_issue.id, result[0][:issue_id]
    end

    test 'handles status transitions from inactive to active' do
      # First closed: Add (active)
      create_closed_issue('12345', 'AIX', 'Add', 5.days.ago)
      # Second closed: Delete (inactive)
      create_closed_issue('12345', 'AIX', 'Delete', 3.days.ago)
      # Third closed: Add again (active - should be current)
      # Use a clearly different timestamp to ensure ordering
      latest_issue = create_closed_issue('12345', 'AIX', 'Add', 1.hour.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'active', result[0][:status]
      assert_equal latest_issue.id, result[0][:issue_id]
    end

    test 'handles status transitions from active to inactive' do
      # First closed: Add (active)
      create_closed_issue('12345', 'PayServ', 'Add', 3.days.ago)
      # Second closed: Delete (inactive - should be current)
      # Use a clearly different timestamp to ensure ordering
      latest_issue = create_closed_issue('12345', 'PayServ', 'Delete', 1.hour.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal 'inactive', result[0][:status]
      assert_equal latest_issue.id, result[0][:issue_id]
    end

    test 'ignores issues without Target System value' do
      # Issue with Target System
      valid_issue = create_closed_issue('12345', 'Oracle / SFMS', 'Add', 1.day.ago)
      # Issue without Target System
      create_closed_issue_without_target_system('12345', 'Add', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal valid_issue.id, result[0][:issue_id]
    end

    test 'ignores issues without Account Action value' do
      # Issue with Account Action
      valid_issue = create_closed_issue('12345', 'AIX', 'Add', 1.day.ago)
      # Issue without Account Action
      create_closed_issue_without_account_action('12345', 'AIX', 1.day.ago)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_equal valid_issue.id, result[0][:issue_id]
    end

    test 'handles employee IDs as integers' do
      create_closed_issue(12345, 'Oracle / SFMS', 'Add', 1.day.ago)

      result = @service.get_account_statuses(12345)

      assert_equal 1, result.length
      assert_equal 'active', result[0][:status]
    end

    test 'handles all supported target systems' do
      systems = ['Oracle / SFMS', 'AIX', 'SFS', 'NYSDS', 'PayServ', 'OGS Swiper Access']

      systems.each do |system|
        create_closed_issue('12345', system, 'Add', 1.day.ago)
      end

      result = @service.get_account_statuses('12345')

      assert_equal systems.length, result.length
      systems.sort.each_with_index do |system, index|
        assert_equal system, result[index][:account_type]
        assert_equal 'active', result[index][:status]
      end
    end

    test 'closed_on timestamp matches issue closed_on' do
      closed_time = 2.days.ago
      issue = create_closed_issue('12345', 'Oracle / SFMS', 'Add', closed_time)

      result = @service.get_account_statuses('12345')

      assert_equal 1, result.length
      assert_in_delta issue.closed_on.to_i, result[0][:closed_on].to_i, 1
    end

    # Tests for get_open_account_requests

    test 'returns empty array for employee with no open issues' do
      result = @service.get_open_account_requests('99999')
      assert_equal [], result
    end

    test 'returns empty array for blank employee ID in open requests' do
      assert_equal [], @service.get_open_account_requests(nil)
      assert_equal [], @service.get_open_account_requests('')
    end

    test 'returns open account requests for employee' do
      issue = create_open_issue('12345', 'Oracle / SFMS', 'Add')

      result = @service.get_open_account_requests('12345')

      assert_equal 1, result.length
      assert_equal 'Oracle / SFMS', result[0][:account_type]
      assert_equal 'Add', result[0][:account_action]
      assert_equal issue.id, result[0][:issue_id]
      assert_equal 'USRA', result[0][:request_code]
    end

    test 'returns multiple open requests for different systems' do
      create_open_issue('12345', 'Oracle / SFMS', 'Add')
      create_open_issue('12345', 'AIX', 'Delete')
      create_open_issue('12345', 'SFS', 'Update Account & Privileges')

      result = @service.get_open_account_requests('12345')

      assert_equal 3, result.length
      # Results should be sorted by account_type
      assert_equal 'AIX', result[0][:account_type]
      assert_equal 'AIXI', result[0][:request_code]

      assert_equal 'Oracle / SFMS', result[1][:account_type]
      assert_equal 'USRA', result[1][:request_code]

      assert_equal 'SFS', result[2][:account_type]
      assert_equal 'SFSU', result[2][:request_code]
    end

    test 'ignores closed issues when getting open requests' do
      create_open_issue('12345', 'Oracle / SFMS', 'Add')
      create_closed_issue('12345', 'AIX', 'Add', 1.day.ago)

      result = @service.get_open_account_requests('12345')

      assert_equal 1, result.length
      assert_equal 'Oracle / SFMS', result[0][:account_type]
    end

    test 'ignores open issues without Target System' do
      valid_issue = create_open_issue('12345', 'Oracle / SFMS', 'Add')
      # Would need a helper to create issue without target system, skipping for now

      result = @service.get_open_account_requests('12345')

      assert_equal 1, result.length
      assert_equal valid_issue.id, result[0][:issue_id]
    end

    private

    def create_or_find_field(name, format, possible_values = nil)
      field = CustomField.find_by(name: name, type: 'IssueCustomField')
      return field if field

      field_attributes = {
        name: name,
        field_format: format,
        is_required: false,
        is_for_all: true,
        trackers: [@tracker]
      }

      # Add possible values for list fields
      if possible_values && format == 'list'
        field_attributes[:possible_values] = possible_values
      end

      IssueCustomField.create!(field_attributes)
    end

    def create_closed_issue(employee_id, target_system, account_action, closed_time)
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        author_id: 1,
        status: @closed_status,
        priority_id: 5,
        subject: "Test Issue - #{employee_id} - #{target_system} - #{account_action}",
        custom_field_values: {
          @employee_id_field.id => employee_id.to_s,
          @target_system_field.id => target_system,
          @account_action_field.id => account_action
        }
      )

      # Set closed_on timestamp using update_all to bypass callbacks
      Issue.where(id: issue.id).update_all(closed_on: closed_time)
      issue.reload
      issue
    end

    def create_open_issue(employee_id, target_system, account_action)
      Issue.create!(
        project: @project,
        tracker: @tracker,
        author_id: 1,
        status: @open_status,
        priority_id: 5,
        subject: "Open Test Issue - #{employee_id} - #{target_system}",
        custom_field_values: {
          @employee_id_field.id => employee_id.to_s,
          @target_system_field.id => target_system,
          @account_action_field.id => account_action
        }
      )
    end

    def create_closed_issue_without_target_system(employee_id, account_action, closed_time)
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        author_id: 1,
        status: @closed_status,
        priority_id: 5,
        subject: "Test Issue - No Target System",
        custom_field_values: {
          @employee_id_field.id => employee_id.to_s,
          @account_action_field.id => account_action
        }
      )

      Issue.where(id: issue.id).update_all(closed_on: closed_time)
      issue.reload
      issue
    end

    def create_closed_issue_without_account_action(employee_id, target_system, closed_time)
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        author_id: 1,
        status: @closed_status,
        priority_id: 5,
        subject: "Test Issue - No Account Action",
        custom_field_values: {
          @employee_id_field.id => employee_id.to_s,
          @target_system_field.id => target_system
        }
      )

      Issue.where(id: issue.id).update_all(closed_on: closed_time)
      issue.reload
      issue
    end
  end
end
