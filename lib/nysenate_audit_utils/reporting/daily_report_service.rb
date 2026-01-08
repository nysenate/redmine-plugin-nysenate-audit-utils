# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class DailyReportService
      attr_reader :from_date, :to_date, :status_changes, :errors

      def initialize(from_date: nil, to_date: nil)
        @from_date = from_date || calculate_default_from_date
        @to_date = to_date || Time.zone.now
        @status_changes = []
        @errors = []
      end

      # Main entry point - generates the full daily report
      def generate
        fetch_status_changes
        initialize_account_tracking_service
        build_report_data
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("DailyReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # Check if report generation was successful
      def success?
        @errors.empty?
      end

      private

      def calculate_default_from_date
        BusinessDayHelper.query_start_date
      end

      def fetch_status_changes
        @status_changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(
          @from_date,
          @to_date
        )
      rescue StandardError => e
        @errors << "Failed to fetch status changes from ESS API: #{e.message}"
        Rails.logger.error("ESS API error: #{e.message}")
        raise
      end

      def initialize_account_tracking_service
        @account_tracking_service = NysenateAuditUtils::AccountTracking::AccountTrackingService.new
      end

      def build_report_data
        return [] if @status_changes.empty?

        # Group status changes by employee_id
        grouped_changes = @status_changes.group_by { |change| change.employee.employee_id }

        grouped_changes.map do |employee_id, changes|
          # Use the first change for employee data (all should be the same employee)
          employee = changes.first.employee

          # Collect all transaction codes and find latest post date
          transaction_codes = changes.map(&:transaction_code).uniq.join(', ')
          latest_post_date = changes.map { |c| c.post_date_time }.compact.max&.to_date

          # Get account statuses and open requests for this employee
          account_statuses = @account_tracking_service.get_account_statuses(employee_id)
          open_requests = @account_tracking_service.get_open_account_requests(employee_id)

          {
            employee_name: employee.display_name,
            account_statuses: account_statuses,
            open_requests: open_requests,
            transaction_codes: transaction_codes,
            phone_number: employee.work_phone,
            office: employee.resp_center_display_name,
            office_location: employee.location&.display_name,
            employee_id: employee_id,
            post_date: latest_post_date
          }
        end
      end
    end
  end
end
