# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class MonthlyReportService
      attr_reader :target_system, :as_of_time, :errors

      def initialize(target_system:, as_of_time: Time.current)
        @target_system = target_system
        @as_of_time = as_of_time
        @errors = []
      end

      # Main entry point - generates the monthly report
      # @return [Array<Hash>, nil] Array of report data hashes or nil on error
      def generate
        validate_target_system
        fetch_account_statuses
        enrich_with_employee_names
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

      def enrich_with_employee_names
        # Get employee name and UID field IDs
        employee_name_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_name_field_id')
        employee_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_uid_field_id')

        return unless employee_name_field_id || employee_uid_field_id

        # Build a hash of issue_id => employee_name for quick lookup
        issue_ids = @account_statuses.map { |status| status[:issue_id] }.compact.uniq
        return if issue_ids.empty?

        # Fetch custom values for employee names and UIDs in a single query
        @employee_names = {}
        @employee_uids = {}

        field_ids = [employee_name_field_id, employee_uid_field_id].compact
        CustomValue
          .where(customized_type: 'Issue', customized_id: issue_ids, custom_field_id: field_ids)
          .each do |cv|
            if cv.custom_field_id == employee_name_field_id
              @employee_names[cv.customized_id] = cv.value
            elsif cv.custom_field_id == employee_uid_field_id
              @employee_uids[cv.customized_id] = cv.value
            end
          end
      rescue StandardError => e
        Rails.logger.error("Failed to enrich with employee data: #{e.message}")
        @employee_names = {}
        @employee_uids = {}
      end

      def build_report_data
        return [] if @account_statuses.nil? || @account_statuses.empty?

        @employee_names ||= {}
        @employee_uids ||= {}

        # Build report data array
        report_data = @account_statuses.map do |status|
          {
            employee_id: status[:employee_id],
            employee_name: @employee_names[status[:issue_id]],
            employee_uid: @employee_uids[status[:issue_id]],
            account_type: status[:account_type],
            status: status[:status],
            account_action: status[:account_action],
            closed_on: status[:closed_on],
            request_code: status[:request_code],
            issue_id: status[:issue_id]
          }
        end

        # Sort by employee_id for consistency
        report_data.sort_by { |row| row[:employee_id].to_i }
      end
    end
  end
end
