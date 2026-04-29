# frozen_string_literal: true

require 'csv'
require 'zip'

module NysenateAuditUtils
  module Reporting
    class CsvGenerator
      DAILY_DESCRIPTION = 'Tickets for employees with status changes in the date range.'
      WEEKLY_DESCRIPTION = 'All tickets active during the week for access list consistency checks.'

      # Generate CSV for daily report data
      # @param data [Array<Hash>] Report data with user and account status info
      # @param from_date [Time, Date, nil] Start of report range
      # @param to_date [Time, Date, nil] End of report range
      # @return [String] CSV content
      def self.generate_daily_csv(data, from_date: nil, to_date: nil)
        return '' unless data

        CSV.generate do |csv|
          if from_date && to_date
            write_metadata(csv,
              name: 'Daily',
              description: DAILY_DESCRIPTION,
              start_time: from_date,
              end_time: to_date
            )
          end

          # Header row
          csv << [
            'Account Holder Name',
            'Account Status',
            'Open Tickets',
            'Transaction Codes',
            'Account Holder Office',
            'Account Holder Location',
            'Account Holder ID',
            'Account Holder Username',
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
              row[:office],
              row[:office_location],
              row[:user_id],
              row[:user_uid],
              row[:post_date]
            ]
          end
        end
      end

      # Generate CSV for weekly report data
      # @param data [Array<Hash>] Report data with issue and user info
      # @param from_date [Time, Date, nil] Start of report range
      # @param to_date [Time, Date, nil] End of report range
      # @return [String] CSV content
      def self.generate_weekly_csv(data, from_date: nil, to_date: nil)
        return '' unless data

        CSV.generate do |csv|
          if from_date && to_date
            write_metadata(csv,
              name: 'Weekly',
              description: WEEKLY_DESCRIPTION,
              start_time: from_date,
              end_time: to_date
            )
          end

          # Header row
          csv << [
            'Ticket #',
            'Account Holder Name',
            'Account Holder Username',
            'Account Holder ID',
            'Account Holder Office',
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
      # @param as_of_time [Time, nil] Snapshot time for the report
      # @param target_system [String, nil] Target system the report covers
      # @return [String] CSV content
      def self.generate_monthly_csv(data, as_of_time: nil, target_system: nil)
        return '' unless data

        CSV.generate do |csv|
          if as_of_time
            description = if target_system
                            "Snapshot of employee access status for #{target_system} as of the end time."
                          else
                            'Snapshot of employee access status as of the end time.'
                          end
            write_metadata(csv,
              name: 'Monthly',
              description: description,
              start_time: 'N/A',
              end_time: as_of_time
            )
          end

          # Header row (matches web view layout with user_type and request_code added)
          csv << [
            'Account Holder Name',
            'Account Holder ID',
            'Account Holder Type',
            'Account Holder Username',
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
      # @param as_of_time [Time, nil] Snapshot time, forwarded as metadata to each CSV
      # @return [String] ZIP binary content
      def self.generate_all_systems_zip(reports_by_system, filename_suffix, as_of_time: nil)
        Zip::OutputStream.write_buffer do |zos|
          reports_by_system.each do |system, data|
            filename = "monthly_report_#{system.parameterize}_#{filename_suffix}.csv"
            zos.put_next_entry(filename)
            zos.write(generate_monthly_csv(data, as_of_time: as_of_time, target_system: system))
          end
        end.string
      end

      # Write the 4-row metadata block followed by a blank separator row.
      def self.write_metadata(csv, name:, description:, start_time:, end_time:)
        csv << ['Report Name', name]
        csv << ['Report Description', description]
        csv << ['Start time', format_metadata_time(start_time)]
        csv << ['End time', format_metadata_time(end_time)]
        csv << ['Generated at', format_metadata_time(Time.current)]
        csv << []
      end

      def self.format_metadata_time(value)
        return value if value.is_a?(String)
        return '' if value.nil?

        # Codebase convention (see commit 56f0835): use system-local time, since
        # Rails Time.zone is unset and in_time_zone shifts to UTC. Only convert
        # Date/DateTime via to_time; Time/TimeWithZone are formatted directly to
        # avoid the Rails 8 to_time-preserves-timezone deprecation.
        time = value.is_a?(Time) ? value : value.to_time
        time.strftime('%Y-%m-%d %H:%M:%S %Z')
      end
    end
  end
end
