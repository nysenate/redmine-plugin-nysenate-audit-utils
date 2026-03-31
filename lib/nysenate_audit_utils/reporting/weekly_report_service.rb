# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class WeeklyReportService
      attr_reader :from_date, :to_date, :errors, :project

      def initialize(project: nil)
        @project = project
        @from_date = Date.current.beginning_of_week # Monday 00:00:00
        @to_date = Time.zone.now
        @errors = []
      end

      # Main entry point - generates the weekly report
      # @return [Array<Hash>, nil] Array of ticket hashes or nil on error
      def generate
        build_report_data
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("WeeklyReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # Check if report generation was successful
      def success?
        @errors.empty?
      end

      private

      def build_report_data
        # Get custom field IDs
        user_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.user_id_field_id
        user_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_uid_field_id')
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        unless user_id_field_id
          @errors << "Employee ID custom field is not configured"
          return []
        end

        # Initialize request code mapper
        request_code_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new

        # Query issues that were active in the current week
        # Active = created or updated during the week
        # Filter by project to only show issues from the specified project
        issues = Issue
          .where(project_id: @project.id)
          .where("(created_on >= ? AND created_on <= ?) OR (updated_on >= ? AND updated_on <= ?)",
                 @from_date, @to_date, @from_date, @to_date)
          .includes(:status, :custom_values)
          .order(updated_on: :desc)

        # Build report data for each issue, filtering out issues without the User ID field configured
        issues.filter_map do |issue|
          # Check if the User ID field is available for this issue
          # Skip issues that don't have this custom field configured
          has_user_id_field = issue.available_custom_fields.any? { |cf| cf.id == user_id_field_id }
          next unless has_user_id_field

          # Get user ID from custom field (may be blank, that's okay)
          user_id = get_custom_field_value(issue, user_id_field_id)

          # Get user UID from custom field (if configured)
          user_uid = if user_uid_field_id
            get_custom_field_value(issue, user_uid_field_id)
          else
            nil
          end

          # Get request code from Account Action and Target System
          request_code = nil
          if account_action_field_id && target_system_field_id
            account_action = get_custom_field_value(issue, account_action_field_id)
            target_system = get_custom_field_value(issue, target_system_field_id)
            request_code = request_code_mapper.get_request_code(account_action, target_system)
          end

          {
            issue_id: issue.id,
            subject: issue.subject,
            status: issue.status.name,
            user_id: user_id,
            user_uid: user_uid,
            request_code: request_code,
            updated_on: issue.updated_on,
            created_on: issue.created_on
          }
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
    end
  end
end
