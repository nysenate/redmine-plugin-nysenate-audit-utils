# frozen_string_literal: true

require 'csv'
require 'zip'

module NysenateAuditUtils
  module Reporting
    class CsvGenerator
      # Generate CSV for daily report data
      # @param data [Array<Hash>] Report data with user and account status info
      # @return [String] CSV content
      def self.generate_daily_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row
          csv << [
            'User Name',
            'Account Status',
            'Open Tickets',
            'Transaction Codes',
            'Phone Number',
            'Office',
            'Office Location',
            'User ID',
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
              row[:user_name],
              account_status_str,
              open_tickets_str,
              row[:transaction_codes],
              row[:phone_number],
              row[:office],
              row[:office_location],
              row[:user_id],
              row[:post_date]
            ]
          end
        end
      end

      # Generate CSV for weekly report data
      # @param data [Array<Hash>] Report data with issue and user info
      # @return [String] CSV content
      def self.generate_weekly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row
          csv << [
            'Ticket #',
            'User Name',
            'User UID',
            'User Number',
            'Office',
            'Request Code',
            'Ticket Description',
            'Status',
            'Open Date',
            'Close Date',
            'Updated On'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:issue_id],
              row[:user_name],
              row[:user_uid],
              row[:user_id],
              row[:office],
              row[:request_code],
              row[:subject],
              row[:status],
              row[:created_on]&.strftime('%Y-%m-%d'),
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:updated_on]&.strftime('%Y-%m-%d %H:%M')
            ]
          end
        end
      end

      # Generate CSV for monthly report data
      # @param data [Array<Hash>] Report data with user account status
      # @return [String] CSV content
      def self.generate_monthly_csv(data)
        return '' unless data

        CSV.generate do |csv|
          # Header row (matches web view layout with user_type and request_code added)
          csv << [
            'User Name',
            'User ID',
            'User Type',
            'User UID',
            'Account Status',
            'Last Updated',
            'Last Issue',
            'Last Action',
            'Request Code'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:user_name],
              row[:user_id],
              row[:user_type],
              row[:user_uid],
              row[:status],
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:issue_id],
              row[:account_action],
              row[:request_code]
            ]
          end
        end
      end
      # Generate a ZIP containing one monthly CSV per target system
      # @param reports_by_system [Hash<String, Array<Hash>>] Map of system name => report data
      # @param filename_suffix [String] Suffix appended to each CSV filename (e.g. "202504" or "current")
      # @return [String] ZIP binary content
      def self.generate_all_systems_zip(reports_by_system, filename_suffix)
        Zip::OutputStream.write_buffer do |zos|
          reports_by_system.each do |system, data|
            filename = "monthly_report_#{system.parameterize}_#{filename_suffix}.csv"
            zos.put_next_entry(filename)
            zos.write(generate_monthly_csv(data))
          end
        end.string
      end
    end
  end
end
