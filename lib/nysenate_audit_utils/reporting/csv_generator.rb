# frozen_string_literal: true

require 'csv'
require 'zip'

module NysenateAuditUtils
  module Reporting
    class CsvGenerator
      DAILY_DESCRIPTION = 'Tickets for employees with status changes in the date range.'
      WEEKLY_DESCRIPTION = 'All tickets active during the week for access list consistency checks.'

      # Weekly report Update Type wording (#18838). The export description and
      # no-entries line name the selected filter; the phrase keeps both sentences
      # grammatical for each option.
      def self.weekly_filter_phrase(update_type)
        case update_type.to_s
        when 'opened' then 'opened'
        when 'closed' then 'closed'
        when 'other'  then 'otherwise-updated'
        else 'updated'
        end
      end

      def self.weekly_description(update_type)
        "All #{weekly_filter_phrase(update_type)} tickets during the query period."
      end

      def self.weekly_no_entries(update_type)
        "No #{weekly_filter_phrase(update_type)} tickets found for the selected period."
      end

      # Report Purpose line (#18834): a "why this report exists" statement shown
      # below the Report Description in the export heading. Only Daily has wording
      # for now; the other reports omit the row until purpose text is decided.
      DAILY_PURPOSE = 'Review for potential Offboarding and/or Onboarding security work.'

      # No-entries messages, mirroring each report's on-screen "none found" text
      # (#18834). Shared here so both the CSV and Excel exporters use identical
      # wording; the interpolated ones (monthly, periodic) are built by helpers.
      DAILY_NO_ENTRIES = 'No user status changes found for the query period.'
      WEEKLY_NO_ENTRIES = 'No closed tickets found for the selected period.'
      PERIODIC_NO_ENTRIES = 'No closed tickets found for the selected period.'
      ACCOUNT_HOLDER_ACCESS_NO_ENTRIES = 'No account access found.'

      # No-entries wording for the Monthly report (mirrors monthly.html.erb).
      def self.monthly_no_entries(target_system, as_of_time)
        base = target_system ? "No account data found for #{target_system}" : 'No account data found'
        as_of_time ? "#{base} as of #{as_of_time.to_date.strftime('%B %Y')}." : "#{base}."
      end

      # No-entries wording for the periodic (SFMS/SFS) report (mirrors periodic.html.erb).
      def self.periodic_no_entries(system, from_date, to_date)
        return PERIODIC_NO_ENTRIES unless system && from_date && to_date

        "No closed #{system.to_s.upcase} tickets found between " \
          "#{from_date.to_date.strftime('%Y-%m-%d')} and #{to_date.to_date.strftime('%Y-%m-%d')}."
      end

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
              purpose: DAILY_PURPOSE,
              start_time: from_date,
              end_time: to_date
            )
          end

          if data.empty?
            csv << [DAILY_NO_ENTRIES]
            next
          end

          # Header row
          csv << [
            'Post Date',
            'Account Holder Name',
            'Account Holder Username',
            'Personnel Status Changes',
            'Account Holder Office',
            'Account Access Status',
            'In-progress Tickets'
          ]

          # Data rows
          data.each do |row|
            # One "CODE - TICKET#" entry per line (blank ticket # falls back to
            # just the code).
            account_status_str = format_code_ticket_lines(row[:account_statuses])
            open_tickets_str = format_code_ticket_lines(row[:open_requests])

            status_changes_str = if row[:status_changes].present?
                                   row[:status_changes].map do |sc|
                                     sc[:notes].present? ? "#{sc[:code]} - #{sc[:notes]}" : sc[:code]
                                   end.join("\n")
                                 else
                                   ''
                                 end

            csv << [
              format_report_date(row[:post_date]),
              row[:user_name],
              row[:user_uid],
              status_changes_str,
              row[:office],
              account_status_str,
              open_tickets_str
            ]
          end
        end
      end

      # Generate CSV for weekly report data
      # @param data [Array<Hash>] Report data with issue and user info
      # @param from_date [Time, Date, nil] Start of report range
      # @param to_date [Time, Date, nil] End of report range
      # @return [String] CSV content
      def self.generate_weekly_csv(data, from_date: nil, to_date: nil, update_type: 'all')
        return '' unless data

        CSV.generate do |csv|
          if from_date && to_date
            write_metadata(csv,
              name: 'Weekly',
              description: weekly_description(update_type),
              start_time: from_date,
              end_time: to_date
            )
          end

          if data.empty?
            csv << [weekly_no_entries(update_type)]
            next
          end

          # Header row
          csv << [
            'Updated On',
            'Open Date',
            'Closed Date',
            'Ticket #',
            'Ticket Status',
            'Subject',
            'Request Code',
            'Account Holder Name',
            'Account Holder Username',
            'Account Holder Office',
            'Account Holder Type',
            'Account Holder ID'
          ]

          # Data rows
          data.each do |row|
            csv << [
              row[:updated_on]&.strftime('%Y-%m-%d %H:%M'),
              row[:created_on]&.strftime('%Y-%m-%d'),
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:issue_id],
              row[:status],
              row[:subject],
              row[:request_code],
              row[:user_name],
              row[:user_uid],
              row[:office],
              row[:user_type],
              row[:user_id]
            ]
          end
        end
      end

      # Generate CSV for the quarterly/annual (periodic) audit report.
      # Columns match the legacy SFMS/SFS audit spreadsheet so the file imports
      # directly into Access. No metadata preamble — the header is the first row.
      # @param data [Array<Hash>] Report rows from PeriodicAuditReportService
      # @return [String] CSV content
      def self.generate_periodic_csv(data, system: nil, from_date: nil, to_date: nil)
        return '' unless data

        CSV.generate do |csv|
          if data.empty?
            csv << [periodic_no_entries(system, from_date, to_date)]
            next
          end

          # Header row (matches the legacy audit spreadsheet). The ticket
          # description is appended as a final export-only column.
          csv << [
            'RequestType',
            'FullName',
            'Userid',
            'Office',
            'EntryDate',
            'CompletedDate',
            'SenDevNumber',
            'GeneralFormInfoID',
            'Program',
            'Subject',
            'Description'
          ]

          data.each do |row|
            csv << [
              row[:request_code],
              row[:user_name],
              row[:user_uid],
              row[:office],
              row[:created_on]&.strftime('%Y-%m-%d'),
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:issue_id],
              nil,
              'SFMS',
              row[:subject],
              row[:description]
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

        include_email = monthly_include_email?(target_system)

        CSV.generate do |csv|
          if as_of_time
            description = monthly_description(target_system)
            write_metadata(csv,
              name: 'Monthly',
              description: description,
              start_time: 'N/A',
              end_time: as_of_time
            )
          end

          if data.empty?
            csv << [monthly_no_entries(target_system, as_of_time)]
            next
          end

          # Header row (matches web view layout with user_type and request_code added)
          header = [
            'Account Holder Name',
            'Account Holder ID',
            'Account Holder Type',
            'Account Holder Username',
            'Account Holder Office',
            'Account Access Status',
            'Last Updated',
            'Last Issue',
            'Last Action',
            'Request Code'
          ]
          header << 'Account Holder Email' if include_email
          csv << header

          # Data rows
          data.each do |row|
            values = [
              row[:user_name],
              row[:user_id],
              row[:user_type],
              row[:user_uid],
              row[:user_office],
              row[:status],
              row[:closed_on]&.strftime('%Y-%m-%d'),
              row[:issue_id],
              row[:account_action],
              row[:request_code]
            ]
            values << row[:user_email] if include_email
            csv << values
          end
        end
      end

      # Report description for the Monthly export, mentioning the target system.
      def self.monthly_description(target_system)
        if target_system
          "Monthly snapshot of account holders with active access for #{target_system}. " \
            'This report displays all access-related tickets closed during the previous month.'
        else
          'Monthly snapshot of account holders with active access. ' \
            'This report displays all access-related tickets closed during the previous month.'
        end
      end

      # Whether the Account Holder Email column should be included for the given
      # target system — true only for the configured public website
      # (public_website_target_system plugin setting).
      def self.monthly_include_email?(target_system)
        configured = NysenateAuditUtils::CustomFieldConfiguration.public_website_target_system
        configured.present? && target_system == configured
      end
      ACCOUNT_HOLDER_ACCESS_DESCRIPTION = 'Account Holder access, including active, inactive, or both statuses, with one row per account.'

      # Generate CSV for the Account Holder Access Report.
      # One row per active account (account holder x target system).
      # @param data [Array<Hash>] Report rows from AccountHolderAccessReportService
      # @return [String] CSV content
      def self.generate_account_holder_access_csv(data)
        return '' unless data

        CSV.generate do |csv|
          write_metadata(csv,
            name: 'Account Holder Access',
            description: ACCOUNT_HOLDER_ACCESS_DESCRIPTION,
            show_times: false
          )

          if data.empty?
            csv << [ACCOUNT_HOLDER_ACCESS_NO_ENTRIES]
            next
          end

          # Header row (Account Holder terminology per plugin convention)
          csv << [
            'Account Holder Name',
            'Account Holder Type',
            'Account Holder Username',
            'Account Holder Office',
            'Target System',
            'Account Access Status',
            'Request Code'
          ]

          data.each do |row|
            csv << [
              row[:user_name],
              row[:user_type],
              row[:user_uid],
              row[:user_office],
              row[:account_type],
              row[:status]&.capitalize,
              row[:request_code]
            ]
          end
        end
      end

      # Generate a ZIP containing one monthly CSV per target system
      # @param reports_by_system [Hash<String, Array<Hash>>] Map of system name => report data
      # @param filename_suffix [String] Suffix appended to each CSV filename
      #   (e.g. "202504" for a month snapshot, or a "20260730" date stamp for current-state)
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

      # Write the metadata block followed by a blank separator row. Reports that
      # have no meaningful time window (e.g. the current-state Account Holder
      # Access report) pass show_times: false to omit the Start/End time rows.
      def self.write_metadata(csv, name:, description:, start_time: nil, end_time: nil, purpose: nil, show_times: true)
        csv << ['Report Name', name]
        csv << ['Report Description', description]
        csv << ['Report Purpose', purpose] if purpose
        if show_times
          csv << ['Start time', format_metadata_time(start_time)]
          csv << ['End time', format_metadata_time(end_time)]
        end
        csv << ['Generated at', format_metadata_time(Time.now)]
        csv << []
      end

      # Render account-status / open-request entries as one "CODE - TICKET#" line
      # each, newline-separated (shared by the CSV and XLSX daily exports). Falls
      # back to the account type when there's no request code, and omits the
      # " - TICKET#" suffix when no issue id is present.
      def self.format_code_ticket_lines(entries)
        return '' if entries.blank?

        entries.map do |entry|
          code = entry[:request_code].presence || entry[:account_type]
          entry[:issue_id].present? ? "#{code} - #{entry[:issue_id]}" : code
        end.join("\n")
      end

      # Format a report date value as YYYY-MM-DD. Coerces Date/Time to a string so
      # Excel doesn't render a bare Date as its numeric serial (e.g. 46188).
      def self.format_report_date(value)
        value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d') : value
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
