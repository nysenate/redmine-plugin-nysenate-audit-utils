# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Builds the Account Holder Access Report: a listing of account access across
    # every target system, each row carrying a derived active/inactive status.
    # Status is determined the same way as the Monthly report — the latest closed
    # Add/Delete ticket for an account holder + target system. If the latest is
    # "Add" the account is active; "Delete" makes it inactive. One row per account
    # (account holder x system), ordered by account holder name. The controller is
    # responsible for filtering by status (defaulting to active only).
    class AccountHolderAccessReportService
      attr_reader :project, :errors

      def initialize(project: nil)
        @project = project
        @errors = []
      end

      # Main entry point - generates the report
      # @return [Array<Hash>, nil] Array of report row hashes or nil on error
      def generate
        statuses = fetch_statuses
        enrich_with_user_names(statuses)
        build_report_data(statuses)
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("AccountHolderAccessReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # Check if report generation was successful
      def success?
        @errors.empty?
      end

      private

      def target_systems
        target_system_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field
        target_system_field&.possible_values || []
      end

      # Gather the account statuses (active and inactive) for every configured
      # target system. Reuses AccountTrackingService#get_account_statuses_by_system,
      # which already returns one status per account holder with the request code
      # of the latest Add/Delete ticket. Status filtering is left to the controller.
      def fetch_statuses
        service = NysenateAuditUtils::AccountTracking::AccountTrackingService.new
        as_of_time = Time.current

        target_systems.flat_map do |system|
          service.get_account_statuses_by_system(system, as_of_time: as_of_time, project: @project)
        end
      end

      # Bulk-fill account holder name / username by issue id, mirroring
      # MonthlyReportService#enrich_with_user_names.
      def enrich_with_user_names(statuses)
        @user_names = {}
        @user_uids = {}
        @user_offices = {}

        user_name_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_name_field_id')
        user_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_uid_field_id')
        user_office_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_location_field_id')
        return unless user_name_field_id || user_uid_field_id || user_office_field_id

        issue_ids = statuses.map { |status| status[:issue_id] }.compact.uniq
        return if issue_ids.empty?

        field_ids = [user_name_field_id, user_uid_field_id, user_office_field_id].compact
        CustomValue
          .where(customized_type: 'Issue', customized_id: issue_ids, custom_field_id: field_ids)
          .each do |cv|
            case cv.custom_field_id
            when user_name_field_id
              @user_names[cv.customized_id] = cv.value
            when user_uid_field_id
              @user_uids[cv.customized_id] = cv.value
            when user_office_field_id
              @user_offices[cv.customized_id] = cv.value
            end
          end
      rescue StandardError => e
        Rails.logger.error("Failed to enrich with user data: #{e.message}")
        @user_names = {}
        @user_uids = {}
        @user_offices = {}
      end

      def build_report_data(statuses)
        @user_names ||= {}
        @user_uids ||= {}
        @user_offices ||= {}

        rows = statuses.map do |status|
          {
            user_name: @user_names[status[:issue_id]],
            user_id: status[:user_id],
            user_uid: @user_uids[status[:issue_id]],
            user_office: @user_offices[status[:issue_id]],
            user_type: status[:user_type],
            account_type: status[:account_type],
            request_code: status[:request_code],
            status: status[:status],
            issue_id: status[:issue_id]
          }
        end

        # Order by account holder name, then system, for a stable default order.
        rows.sort_by { |row| [row[:user_name].to_s.downcase, row[:account_type].to_s] }
      end
    end
  end
end
