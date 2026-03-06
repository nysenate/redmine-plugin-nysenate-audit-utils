# frozen_string_literal: true

require 'csv'

module NysenateAuditUtils
  module Reporting
    class CsvGenerator
      # Generate CSV for daily report data
      # @param data [Array<Hash>] Report data with subject and account status info
      # @return [String] CSV content
      def self.generate_daily_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row (using "Subject" terminology for consistency, though daily reports are employee-only)
          csv << [
            'Subject Name',
            'Account Status',
            'Open Tickets',
            'Transaction Codes',
            'Phone Number',
            'Office',
            'Office Location',
            'Subject ID',
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
              row[:subject_name],
              account_status_str,
              open_tickets_str,
              row[:transaction_codes],
              row[:phone_number],
              row[:office],
              row[:office_location],
              row[:subject_id],
              row[:post_date]
            ]
          end
        end
      end

      # Generate CSV for weekly report data
      # @param data [Array<Hash>] Report data with issue and subject info
      # @return [String] CSV content
      def self.generate_weekly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row (using "Subject" terminology for consistency)
          csv << [
            'Subject UID',
            'Subject Number',
            'Request Code',
            'Ticket Description',
            'Status',
            'Updated On'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:subject_uid],
              row[:subject_id],
              row[:request_code],
              row[:subject],
              row[:status],
              row[:updated_on]&.strftime('%Y-%m-%d %H:%M')
            ]
          end
        end
      end

      # Generate CSV for monthly report data
      # @param data [Array<Hash>] Report data with subject account status
      # @return [String] CSV content
      def self.generate_monthly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row (matches web view layout with subject_type and request_code added)
          csv << [
            'Subject Name',
            'Subject ID',
            'Subject Type',
            'Subject UID',
            'Account Status',
            'Last Updated',
            'Last Issue',
            'Last Action',
            'Request Code'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:subject_name],
              row[:subject_id],
              row[:subject_type],
              row[:subject_uid],
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
