# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class MonthlyReportService
      attr_reader :target_system, :as_of_time, :status_filter, :errors

      def initialize(target_system:, as_of_time: Time.current, status_filter: 'all')
        @target_system = target_system
        @as_of_time = as_of_time
        @status_filter = status_filter
        @errors = []
      end

      # Main entry point - generates the monthly report
      # @return [Array<Hash>, nil] Array of report data hashes or nil on error
      def generate
        validate_target_system
        fetch_account_statuses
        enrich_with_user_names
        build_report_data
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("MonthlyReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # Check if report generation was successful
      def success?
        @errors.empty?
      end

      private

      def validate_target_system
        # Allow blank target system (will return empty results)
        return if @target_system.blank?

        # Get valid target systems from custom field configuration
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        # If field is not configured, allow any target system
        return unless target_system_field_id

        target_system_field = CustomField.find_by(id: target_system_field_id)

        # If field doesn't exist, allow any target system
        return unless target_system_field

        # Check if target system is in valid list
        valid_systems = target_system_field.possible_values || []
        return if valid_systems.empty? || valid_systems.include?(@target_system)

        # Invalid target system - raise error
        @errors << "Invalid target system: #{@target_system}"
        raise ArgumentError, "Invalid target system: #{@target_system}"
      end

      def fetch_account_statuses
        account_tracking_service = NysenateAuditUtils::AccountTracking::AccountTrackingService.new
        @account_statuses = account_tracking_service.get_account_statuses_by_system(@target_system, as_of_time: @as_of_time)
      rescue StandardError => e
        @errors << "Failed to fetch account statuses: #{e.message}"
        Rails.logger.error("Account status fetch error: #{e.message}")
        raise
      end

      def enrich_with_user_names
        # Get user name, UID, and type field IDs
        user_name_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_name_field_id')
        user_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_uid_field_id')
        user_type_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_type_field_id')

        return unless user_name_field_id || user_uid_field_id

        # Build a hash of issue_id => user_name for quick lookup
        issue_ids = @account_statuses.map { |status| status[:issue_id] }.compact.uniq
        return if issue_ids.empty?

        # Fetch custom values for user names, UIDs, and types in a single query
        @user_names = {}
        @user_uids = {}
        @user_types = {}

        field_ids = [user_name_field_id, user_uid_field_id, user_type_field_id].compact
        CustomValue
          .where(customized_type: 'Issue', customized_id: issue_ids, custom_field_id: field_ids)
          .each do |cv|
            if cv.custom_field_id == user_name_field_id
              @user_names[cv.customized_id] = cv.value
            elsif cv.custom_field_id == user_uid_field_id
              @user_uids[cv.customized_id] = cv.value
            elsif cv.custom_field_id == user_type_field_id
              @user_types[cv.customized_id] = cv.value
            end
          end
      rescue StandardError => e
        Rails.logger.error("Failed to enrich with user data: #{e.message}")
        @user_names = {}
        @user_uids = {}
        @user_types = {}
      end

      def build_report_data
        return [] if @account_statuses.nil? || @account_statuses.empty?

        @user_names ||= {}
        @user_uids ||= {}
        @user_types ||= {}

        # Build report data array
        report_data = @account_statuses.map do |status|
          {
            user_id: status[:user_id],
            user_name: @user_names[status[:issue_id]],
            user_uid: @user_uids[status[:issue_id]],
            user_type: @user_types[status[:issue_id]] || status[:user_type],  # Prefer from enrichment, fall back to status hash
            account_type: status[:account_type],
            status: status[:status],
            account_action: status[:account_action],
            closed_on: status[:closed_on],
            request_code: status[:request_code],
            issue_id: status[:issue_id]
          }
        end

        # Apply status filter
        report_data = filter_by_status(report_data)

        # Sort by user_id for consistency
        report_data.sort_by { |row| row[:user_id].to_i rescue row[:user_id].to_s }  # Handle both numeric and prefixed IDs
      end

      # Filter report data by account status
      # @param data [Array<Hash>] Array of report data hashes
      # @return [Array<Hash>] Filtered array of report data
      def filter_by_status(data)
        return data if @status_filter == 'all' || @status_filter.blank?

        data.select do |row|
          row[:status] == @status_filter
        end
      end
    end
  end
end
