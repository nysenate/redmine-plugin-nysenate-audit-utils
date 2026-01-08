# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class WeeklyReportService
      attr_reader :from_date, :to_date, :errors

      def initialize
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
        employee_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.employee_id_field_id
        employee_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('employee_uid_field_id')
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        unless employee_id_field_id
          @errors << "Employee ID custom field is not configured"
          return []
        end

        # Initialize request code mapper
        request_code_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new

        # Query issues that were active in the current week
        # Active = created or updated during the week
        issues = Issue
          .where("(created_on >= ? AND created_on <= ?) OR (updated_on >= ? AND updated_on <= ?)",
                 @from_date, @to_date, @from_date, @to_date)
          .includes(:status, :custom_values)
          .order(updated_on: :desc)

        # Build report data for each issue
        issues.map do |issue|
          # Get employee ID from custom field
          employee_id = get_custom_field_value(issue, employee_id_field_id)

          # Get employee UID from custom field (if configured)
          employee_uid = if employee_uid_field_id
            get_custom_field_value(issue, employee_uid_field_id)
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
            employee_id: employee_id,
            employee_uid: employee_uid,
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
