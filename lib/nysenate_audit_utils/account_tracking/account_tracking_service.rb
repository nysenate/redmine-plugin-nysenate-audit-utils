# frozen_string_literal: true

module NysenateAuditUtils
  module AccountTracking
    # Service for tracking account status history based on closed issues
    # Determines current active/inactive status of subject accounts across different systems
    class AccountTrackingService
      # Account actions that indicate an active account
      ACTIVE_ACTIONS = ['Add', 'Update Account & Privileges', 'Update Privileges Only', 'Update Account Only'].freeze
      # Account action that indicates an inactive account
      INACTIVE_ACTION = 'Delete'

      # Get account statuses for a specific subject
      # @param subject_id [String] The subject ID to query
      # @return [Array<Hash>] Array of account status hashes, one per account type
      # Each hash contains:
      #   - subject_id: The subject ID
      #   - subject_type: The subject type (Employee, Vendor, etc.)
      #   - account_type: The Target System value (e.g., "Oracle / SFMS")
      #   - status: "active" or "inactive"
      #   - issue_id: ID of the most recent closed issue for this account type
      #   - closed_on: Date when the issue was closed
      #   - account_action: The Account Action value from the latest issue
      #   - request_code: The BACHelp request code (e.g., "USRA", "AIXI")
      def get_account_statuses(subject_id)
        return [] if subject_id.blank?

        # Get custom field IDs
        subject_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_id_field_id
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        # Validate required fields exist
        unless subject_id_field_id && account_action_field_id && target_system_field_id
          raise 'Required custom fields not found. Ensure Subject ID, Account Action, and Target System fields are configured.'
        end

        # Query closed issues for this subject
        issues = find_closed_issues_for_subject(subject_id, subject_id_field_id)

        # Group issues by Target System (account type)
        issues_by_account_type = group_issues_by_account_type(
          issues,
          target_system_field_id,
          account_action_field_id
        )

        # Build account status data for each account type
        build_account_statuses(issues_by_account_type, subject_id)
      end

      # Get open account requests for a specific subject
      # @param subject_id [String] The subject ID to query
      # @return [Array<Hash>] Array of open request hashes
      # Each hash contains:
      #   - subject_id: The subject ID
      #   - subject_type: The subject type (Employee, Vendor, etc.)
      #   - account_type: The Target System value (e.g., "Oracle / SFMS")
      #   - account_action: The Account Action value
      #   - issue_id: ID of the open issue
      #   - request_code: The BACHelp request code (e.g., "USRA", "AIXI")
      def get_open_account_requests(subject_id)
        return [] if subject_id.blank?

        # Get custom field IDs
        subject_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_id_field_id
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        # Validate required fields exist
        unless subject_id_field_id && account_action_field_id && target_system_field_id
          raise 'Required custom fields not found. Ensure Subject ID, Account Action, and Target System fields are configured.'
        end

        # Query open issues for this subject
        issues = find_open_issues_for_subject(subject_id, subject_id_field_id)

        # Build open request data
        build_open_requests(issues, target_system_field_id, account_action_field_id, subject_id)
      end

      # Get account statuses for all subjects with accounts on a specific target system
      # @param target_system [String] The target system to query (e.g., "Oracle / SFMS", "AIX")
      # @param as_of_time [Time] The cutoff time for the report (default: current time)
      # @return [Array<Hash>] Array of account status hashes, one per subject
      # Each hash contains:
      #   - subject_id: The subject ID
      #   - subject_type: The subject type (Employee, Vendor, etc.)
      #   - account_type: The Target System value (same as target_system parameter)
      #   - status: "active" or "inactive"
      #   - issue_id: ID of the most recent closed issue for this subject/system
      #   - closed_on: Date when the issue was closed
      #   - account_action: The Account Action value from the latest issue
      #   - request_code: The BACHelp request code (e.g., "USRA", "AIXI")
      def get_account_statuses_by_system(target_system, as_of_time: Time.current)
        return [] if target_system.blank?

        # Get custom field IDs
        subject_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_id_field_id
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        # Validate required fields exist
        unless subject_id_field_id && account_action_field_id && target_system_field_id
          raise 'Required custom fields not found. Ensure Subject ID, Account Action, and Target System fields are configured.'
        end

        # Single bulk query for all closed issues matching this target system
        # Uses efficient joins to get all needed data in one query
        results = find_closed_issues_by_target_system(
          target_system,
          subject_id_field_id,
          account_action_field_id,
          target_system_field_id,
          as_of_time
        )

        # Group by subject_id and build account status data
        build_account_statuses_by_subject(results, target_system)
      end

      private

      # Find all closed issues for a subject
      # @param subject_id [String] The subject ID
      # @param subject_id_field_id [Integer] The Subject ID custom field ID
      # @return [ActiveRecord::Relation] Closed issues for the subject
      def find_closed_issues_for_subject(subject_id, subject_id_field_id)
        # Get issue IDs for this subject
        issue_ids = CustomValue
          .where(customized_type: 'Issue')
          .where(custom_field_id: subject_id_field_id)
          .where(value: subject_id.to_s)
          .pluck(:customized_id)

        return Issue.none if issue_ids.empty?

        # Get only closed issues, ordered by closed_on date (most recent first)
        Issue
          .where(id: issue_ids)
          .joins(:status)
          .where(issue_statuses: { is_closed: true })
          .where.not(closed_on: nil)
          .includes(:custom_values)
          .order(closed_on: :desc)
      end

      # Find all open issues for a subject
      # @param subject_id [String] The subject ID
      # @param subject_id_field_id [Integer] The Subject ID custom field ID
      # @return [ActiveRecord::Relation] Open issues for the subject
      def find_open_issues_for_subject(subject_id, subject_id_field_id)
        # Get issue IDs for this subject
        issue_ids = CustomValue
          .where(customized_type: 'Issue')
          .where(custom_field_id: subject_id_field_id)
          .where(value: subject_id.to_s)
          .pluck(:customized_id)

        return Issue.none if issue_ids.empty?

        # Get only open issues
        Issue
          .where(id: issue_ids)
          .joins(:status)
          .where(issue_statuses: { is_closed: false })
          .includes(:custom_values)
      end

      # Group issues by their Target System value
      # @param issues [ActiveRecord::Relation] Issues to group
      # @param target_system_field_id [Integer] Target System custom field ID
      # @param account_action_field_id [Integer] Account Action custom field ID
      # @return [Hash] Hash mapping target_system => array of issue data hashes
      def group_issues_by_account_type(issues, target_system_field_id, account_action_field_id)
        grouped = Hash.new { |h, k| h[k] = [] }

        issues.each do |issue|
          target_system = get_custom_field_value(issue, target_system_field_id)
          account_action = get_custom_field_value(issue, account_action_field_id)

          # Skip issues without target system or account action
          next if target_system.blank? || account_action.blank?

          grouped[target_system] << {
            issue_id: issue.id,
            closed_on: issue.closed_on,
            account_action: account_action,
            issue: issue  # Include issue object for extracting subject_type
          }
        end

        grouped
      end

      # Build account status data from grouped issues
      # @param issues_by_account_type [Hash] Hash of target_system => array of issue data
      # @param subject_id [String] The subject ID
      # @return [Array<Hash>] Array of account status hashes
      def build_account_statuses(issues_by_account_type, subject_id)
        mapper = request_code_mapper
        subject_type_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_type_field_id

        issues_by_account_type.map do |account_type, issue_data_list|
          # Get the most recent issue (first in the list, as issues are sorted by closed_on desc)
          latest_issue = issue_data_list.first

          # Get subject_type from the latest issue
          subject_type = if subject_type_field_id && latest_issue[:issue]
                           get_custom_field_value(latest_issue[:issue], subject_type_field_id)
                         end

          {
            subject_id: subject_id,
            subject_type: subject_type,
            account_type: account_type,
            status: determine_status(latest_issue[:account_action]),
            issue_id: latest_issue[:issue_id],
            closed_on: latest_issue[:closed_on],
            account_action: latest_issue[:account_action],
            request_code: mapper.get_request_code(latest_issue[:account_action], account_type)
          }
        end.sort_by { |status| status[:account_type] } # Sort by account type for consistent output
      end

      # Build open request data from issues
      # @param issues [ActiveRecord::Relation] Open issues to process
      # @param target_system_field_id [Integer] Target System custom field ID
      # @param account_action_field_id [Integer] Account Action custom field ID
      # @param subject_id [String] The subject ID
      # @return [Array<Hash>] Array of open request hashes
      def build_open_requests(issues, target_system_field_id, account_action_field_id, subject_id)
        mapper = request_code_mapper
        subject_type_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_type_field_id

        issues.map do |issue|
          target_system = get_custom_field_value(issue, target_system_field_id)
          account_action = get_custom_field_value(issue, account_action_field_id)
          subject_type = get_custom_field_value(issue, subject_type_field_id) if subject_type_field_id

          # Skip issues without required fields
          next if target_system.blank? || account_action.blank?

          {
            subject_id: subject_id,
            subject_type: subject_type,
            account_type: target_system,
            account_action: account_action,
            issue_id: issue.id,
            request_code: mapper.get_request_code(account_action, target_system)
          }
        end.compact.sort_by { |request| request[:account_type] }
      end

      # Determine if an account is active or inactive based on the account action
      # @param account_action [String] The Account Action value
      # @return [String] "active" or "inactive"
      def determine_status(account_action)
        if account_action == INACTIVE_ACTION
          'inactive'
        elsif ACTIVE_ACTIONS.include?(account_action)
          'active'
        else
          # Default to active for any unrecognized action
          'active'
        end
      end

      # Get custom field value from an issue
      # @param issue [Issue] The issue
      # @param field_id [Integer] The custom field ID
      # @return [String, nil] The field value or nil
      def get_custom_field_value(issue, field_id)
        custom_value = issue.custom_values.find { |cv| cv.custom_field_id == field_id }
        custom_value&.value
      end

      # Get the request code mapper instance
      # @return [NysenateAuditUtils::RequestCodes::RequestCodeMapper] The mapper instance
      def request_code_mapper
        @request_code_mapper ||= begin
          custom_mappings = Setting.plugin_nysenate_audit_utils['request_code_mappings'] || {}
          NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(custom_mappings)
        end
      end

      # Find all closed issues for a specific target system using efficient bulk query
      # @param target_system [String] The target system value
      # @param subject_id_field_id [Integer] Subject ID custom field ID
      # @param account_action_field_id [Integer] Account Action custom field ID
      # @param target_system_field_id [Integer] Target System custom field ID
      # @param as_of_time [Time] The cutoff time for the report
      # @return [Array<Hash>] Array of hashes with subject_id, subject_type, account_action, issue_id, closed_on
      def find_closed_issues_by_target_system(target_system, subject_id_field_id, account_action_field_id, target_system_field_id, as_of_time)
        # Query strategy: Single bulk query using joins to get all data at once
        # This avoids N+1 queries by fetching everything in one database round trip

        # Find all issue IDs that have the specified target system
        issue_ids_with_target_system = CustomValue
          .where(customized_type: 'Issue')
          .where(custom_field_id: target_system_field_id)
          .where(value: target_system)
          .pluck(:customized_id)

        return [] if issue_ids_with_target_system.empty?

        # Get closed issues with all custom field values included
        closed_issues = Issue
          .where(id: issue_ids_with_target_system)
          .joins(:status)
          .where(issue_statuses: { is_closed: true })
          .where.not(closed_on: nil)
          .where('issues.closed_on <= ?', as_of_time)
          .includes(:custom_values)
          .order(closed_on: :desc)

        # Get subject_type field ID
        subject_type_field_id = NysenateAuditUtils::CustomFieldConfiguration.subject_type_field_id

        # Extract data from issues and their custom values
        closed_issues.map do |issue|
          subject_id = get_custom_field_value(issue, subject_id_field_id)
          account_action = get_custom_field_value(issue, account_action_field_id)
          subject_type = get_custom_field_value(issue, subject_type_field_id) if subject_type_field_id

          # Skip issues without required data
          next if subject_id.blank? || account_action.blank?

          {
            subject_id: subject_id,
            subject_type: subject_type,
            account_action: account_action,
            issue_id: issue.id,
            closed_on: issue.closed_on
          }
        end.compact
      end

      # Build account status data grouped by subject
      # @param results [Array<Hash>] Array of issue data hashes from find_closed_issues_by_target_system
      # @param target_system [String] The target system value
      # @return [Array<Hash>] Array of account status hashes, one per subject
      def build_account_statuses_by_subject(results, target_system)
        mapper = request_code_mapper

        # Group by subject_id
        grouped = results.group_by { |r| r[:subject_id] }

        # For each subject, take the most recent issue (first one due to DESC ordering)
        statuses = grouped.map do |subject_id, subject_issues|
          latest_issue = subject_issues.first

          {
            subject_id: subject_id,
            subject_type: latest_issue[:subject_type],
            account_type: target_system,
            status: determine_status(latest_issue[:account_action]),
            issue_id: latest_issue[:issue_id],
            closed_on: latest_issue[:closed_on],
            account_action: latest_issue[:account_action],
            request_code: mapper.get_request_code(latest_issue[:account_action], target_system)
          }
        end

        # Sort by subject_id for consistent output
        statuses.sort_by { |s| s[:subject_id] }
      end
    end
  end
end
