# frozen_string_literal: true

require 'csv'

module NysenateAuditUtils
  module Reporting
    class CsvGenerator
      # Generate CSV for daily report data
      # @param data [Array<Hash>] Report data with employee and account status info
      # @return [String] CSV content
      def self.generate_daily_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row
          csv << [
            'Employee Name',
            'Account Status',
            'Open Tickets',
            'Transaction Codes',
            'Phone Number',
            'Office',
            'Office Location',
            'Employee ID',
            'Post Date'
          ]

          # Data rows
          data.each do |row|
            # Format account statuses as comma-separated request codes
            account_status_str = if row[:account_statuses].present?
              row[:account_statuses].map { |s| s[:request_code] || s[:account_type] }.join(', ')
            else
              ''
            end

            # Format open requests as comma-separated request codes
            open_tickets_str = if row[:open_requests].present?
              row[:open_requests].map { |r| r[:request_code] || r[:account_type] }.join(', ')
            else
              ''
            end

            csv << [
              row[:employee_name],
              account_status_str,
              open_tickets_str,
              row[:transaction_codes],
              row[:phone_number],
              row[:office],
              row[:office_location],
              row[:employee_id],
              row[:post_date]
            ]
          end
        end
      end

      # Generate CSV for weekly report data
      # @param data [Array<Hash>] Report data with issue and employee info
      # @return [String] CSV content
      def self.generate_weekly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row
          csv << [
            'Employee UID',
            'Employee Number',
            'Request Code',
            'Ticket Description',
            'Status',
            'Updated On'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:employee_uid],
              row[:employee_id],
              row[:request_code],
              row[:subject],
              row[:status],
              row[:updated_on]&.strftime('%Y-%m-%d %H:%M')
            ]
          end
        end
      end

      # Generate CSV for monthly report data
      # @param data [Array<Hash>] Report data with employee account status
      # @return [String] CSV content
      def self.generate_monthly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row (matches web view layout with request_code added)
          csv << [
            'Employee Name',
            'Employee ID',
            'Employee UID',
            'Account Status',
            'Last Updated',
            'Last Issue',
            'Last Action',
            'Request Code'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:employee_name],
              row[:employee_id],
              row[:employee_uid],
              row[:status],
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:issue_id],
              row[:account_action],
              row[:request_code]
            ]
          end
        end
      end
    end
  end
end
