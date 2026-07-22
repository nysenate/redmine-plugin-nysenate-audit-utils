# frozen_string_literal: true

require 'caxlsx'

module NysenateAuditUtils
  module Reporting
    # Formatted Excel (.xlsx) equivalents of the CsvGenerator report exports.
    #
    # Each public +generate_*_xlsx+ method mirrors the column layout of its
    # CsvGenerator counterpart so the two formats stay in lockstep, and returns
    # the serialized workbook as a binary String (ready for +send_data+ /
    # mail attachments). The shared private helpers (build_package,
    # write_metadata_rows, write_table) are the "build once" piece the
    # individual exporters build on: styled heading, styled table header,
    # bordered wrapping body cells, and sensible column widths.
    class XlsxGenerator
      # Reuse the exact metadata copy from the CSV generator so both exports read
      # identically.
      DAILY_DESCRIPTION = CsvGenerator::DAILY_DESCRIPTION
      WEEKLY_DESCRIPTION = CsvGenerator::WEEKLY_DESCRIPTION
      ACCOUNT_HOLDER_ACCESS_DESCRIPTION = CsvGenerator::ACCOUNT_HOLDER_ACCESS_DESCRIPTION
      DAILY_PURPOSE = CsvGenerator::DAILY_PURPOSE

      # Generate the Daily report workbook.
      # @param data [Array<Hash>] rows from DailyReportService
      # @param from_date [Time, Date, nil]
      # @param to_date [Time, Date, nil]
      # @return [String] xlsx binary
      def self.generate_daily_xlsx(data, from_date: nil, to_date: nil)
        return ''.b unless data

        build_package do |wb, styles|
          wb.add_worksheet(name: 'Daily') do |sheet|
            if from_date && to_date
              write_metadata_rows(sheet, styles,
                name: 'Daily',
                description: DAILY_DESCRIPTION,
                purpose: DAILY_PURPOSE,
                start_time: from_date,
                end_time: to_date
              )
            end

            if data.empty?
              write_no_entries(sheet, styles, CsvGenerator::DAILY_NO_ENTRIES)
              next
            end

            headers = [
              'Account Holder Name',
              'Account Status',
              'Open Tickets',
              'Status Changes',
              'Account Holder Office',
              'Account Holder Location',
              'Account Holder ID',
              'Account Holder Username',
              'Post Date'
            ]

            rows = data.map do |row|
              account_status_str = if row[:account_statuses].present?
                                     row[:account_statuses].map { |s| s[:request_code] || s[:account_type] }.join(', ')
                                   else
                                     ''
                                   end

              open_tickets_str = if row[:open_requests].present?
                                   row[:open_requests].map { |r| r[:request_code] || r[:account_type] }.join(', ')
                                 else
                                   ''
                                 end

              status_changes_str = if row[:status_changes].present?
                                     row[:status_changes].map do |sc|
                                       sc[:notes].present? ? "#{sc[:code]} - #{sc[:notes]}" : sc[:code]
                                     end.join("\n")
                                   else
                                     ''
                                   end

              [
                row[:user_name],
                account_status_str,
                open_tickets_str,
                status_changes_str,
                row[:office],
                row[:office_location],
                row[:user_id],
                row[:user_uid],
                row[:post_date]
              ]
            end

            write_table(sheet, styles,
              headers: headers,
              rows: rows,
              widths: [24, 16, 16, 40, 20, 20, 14, 20, 14]
            )
          end
        end
      end

      # Generate the Weekly report workbook.
      # @param data [Array<Hash>] rows from WeeklyReportService
      def self.generate_weekly_xlsx(data, from_date: nil, to_date: nil)
        return ''.b unless data

        build_package do |wb, styles|
          wb.add_worksheet(name: 'Weekly') do |sheet|
            if from_date && to_date
              write_metadata_rows(sheet, styles,
                name: 'Weekly',
                description: WEEKLY_DESCRIPTION,
                start_time: from_date,
                end_time: to_date
              )
            end

            if data.empty?
              write_no_entries(sheet, styles, CsvGenerator::WEEKLY_NO_ENTRIES)
              next
            end

            headers = [
              'Ticket #',
              'Account Holder Type',
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

            rows = data.map do |row|
              [
                row[:issue_id],
                row[:user_type],
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

            write_table(sheet, styles,
              headers: headers,
              rows: rows,
              widths: [10, 16, 24, 20, 14, 20, 14, 44, 14, 14, 14, 18]
            )
          end
        end
      end

      # Generate the quarterly/annual (periodic) audit workbook. Columns match
      # the legacy SFMS/SFS audit spreadsheet; no metadata preamble.
      # @param data [Array<Hash>] rows from PeriodicAuditReportService
      def self.generate_periodic_xlsx(data, system: nil, from_date: nil, to_date: nil)
        return ''.b unless data

        build_package do |wb, styles|
          wb.add_worksheet(name: 'Audit') do |sheet|
            if data.empty?
              write_no_entries(sheet, styles, CsvGenerator.periodic_no_entries(system, from_date, to_date))
              next
            end

            headers = [
              'RequestType',
              'FullName',
              'Userid',
              'Office',
              'EntryDate',
              'CompletedDate',
              'BacNumber',
              'SenDevNumber',
              'GeneralFormInfoID',
              'Program',
              'Description'
            ]

            rows = data.map do |row|
              [
                row[:request_code],
                row[:user_name],
                row[:user_uid],
                row[:office],
                row[:created_on]&.strftime('%Y-%m-%d'),
                row[:closed_on]&.strftime('%Y-%m-%d'),
                row[:bac_number],
                row[:issue_id],
                nil,
                'SFMS',
                row[:subject]
              ]
            end

            write_table(sheet, styles,
              headers: headers,
              rows: rows,
              widths: [14, 24, 14, 20, 14, 16, 14, 14, 18, 12, 44]
            )
          end
        end
      end

      # Generate the Monthly report workbook for a single target system.
      # @param data [Array<Hash>] rows from MonthlyReportService
      # @param as_of_time [Time, nil]
      # @param target_system [String, nil]
      def self.generate_monthly_xlsx(data, as_of_time: nil, target_system: nil)
        return ''.b unless data

        build_package do |wb, styles|
          wb.add_worksheet(name: sanitize_sheet_name(target_system || 'Monthly')) do |sheet|
            write_monthly_sheet(sheet, styles, data, as_of_time: as_of_time, target_system: target_system)
          end
        end
      end

      # Generate a single workbook with one worksheet per target system.
      # @param reports_by_system [Hash<String, Array<Hash>>]
      # @param as_of_time [Time, nil]
      def self.generate_all_systems_xlsx(reports_by_system, as_of_time: nil)
        build_package do |wb, styles|
          reports_by_system.each do |system, data|
            wb.add_worksheet(name: sanitize_sheet_name(system)) do |sheet|
              write_monthly_sheet(sheet, styles, data, as_of_time: as_of_time, target_system: system)
            end
          end
        end
      end

      # Generate the Account Holder Access workbook (one row per active account).
      # @param data [Array<Hash>] rows from AccountHolderAccessReportService
      def self.generate_account_holder_access_xlsx(data)
        return ''.b unless data

        build_package do |wb, styles|
          wb.add_worksheet(name: 'Account Holder Access') do |sheet|
            write_metadata_rows(sheet, styles,
              name: 'Account Holder Access',
              description: ACCOUNT_HOLDER_ACCESS_DESCRIPTION,
              start_time: 'N/A',
              end_time: Time.now
            )

            if data.empty?
              write_no_entries(sheet, styles, CsvGenerator::ACCOUNT_HOLDER_ACCESS_NO_ENTRIES)
              next
            end

            headers = [
              'Account Holder Name',
              'Account Holder Type',
              'Account Holder Username',
              'Account Holder Office',
              'Target System',
              'Account Status',
              'Request Code'
            ]

            rows = data.map do |row|
              [
                row[:user_name],
                row[:user_type],
                row[:user_uid],
                row[:user_office],
                row[:account_type],
                row[:status]&.capitalize,
                row[:request_code]
              ]
            end

            write_table(sheet, styles,
              headers: headers,
              rows: rows,
              widths: [24, 16, 20, 20, 18, 16, 14]
            )
          end
        end
      end

      # --- Shared helpers ------------------------------------------------------

      # Build a package with the shared style set, yield (workbook, styles) for
      # sheet construction, and return the serialized xlsx String.
      def self.build_package
        package = Axlsx::Package.new
        wb = package.workbook
        styles = build_styles(wb)
        yield wb, styles
        package.to_stream.read
      end

      # Define the reusable styles once per workbook.
      # @return [Hash{Symbol=>Integer}] style ids keyed by role
      def self.build_styles(wb)
        {
          metadata_label: wb.styles.add_style(b: true, alignment: { wrap_text: true, vertical: :top }),
          section_title: wb.styles.add_style(b: true, sz: 13),
          no_entries: wb.styles.add_style(i: true, fg_color: '808080'),
          header: wb.styles.add_style(
            b: true,
            bg_color: 'D9E1F2',
            # Explicit dark font so the light-blue fill stays legible; without it
            # the table style's header formatting renders white-on-light-blue.
            fg_color: '1F3864',
            border: { style: :thin, color: 'B0B0B0' },
            # Wrap long column names and top-align so the header row auto-scales
            # its height to fit the wrapped text.
            alignment: { vertical: :top, wrap_text: true }
          ),
          body: wb.styles.add_style(
            border: { style: :thin, color: 'D0D0D0' },
            alignment: { wrap_text: true, vertical: :top }
          )
        }
      end

      # Write a monthly report worksheet (metadata + table). Shared by the
      # single-system and all-systems (multi-sheet) workbooks.
      def self.write_monthly_sheet(sheet, styles, data, as_of_time:, target_system:)
        if as_of_time
          description = if target_system
                          "Snapshot of employee access status for #{target_system} as of the end time."
                        else
                          'Snapshot of employee access status as of the end time.'
                        end
          write_metadata_rows(sheet, styles,
            name: 'Monthly',
            description: description,
            start_time: 'N/A',
            end_time: as_of_time
          )
        end

        if data.empty?
          write_no_entries(sheet, styles, CsvGenerator.monthly_no_entries(target_system, as_of_time))
          return
        end

        headers = [
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

        rows = data.map do |row|
          [
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

        write_table(sheet, styles,
          headers: headers,
          rows: rows,
          widths: [24, 14, 16, 20, 16, 14, 12, 20, 14]
        )
      end

      # Write the metadata preamble (parity with CsvGenerator.write_metadata)
      # followed by a blank separator row.
      def self.write_metadata_rows(sheet, styles, name:, description:, start_time:, end_time:, purpose: nil)
        label = styles[:metadata_label]
        sheet.add_row ['Report Name', name], style: [label, nil]
        sheet.add_row ['Report Description', description], style: [label, nil]
        sheet.add_row(['Report Purpose', purpose], style: [label, nil]) if purpose
        sheet.add_row ['Start time', CsvGenerator.format_metadata_time(start_time)], style: [label, nil]
        sheet.add_row ['End time', CsvGenerator.format_metadata_time(end_time)], style: [label, nil]
        sheet.add_row ['Generated at', CsvGenerator.format_metadata_time(Time.now)], style: [label, nil]
        sheet.add_row []
      end

      # Write a styled header row + bordered wrapping body rows as a real Excel
      # table (filterable/sortable, structured), and set column widths. Row
      # heights are left unset so Excel auto-fits the wrapped header + content.
      # @param widths [Array<Numeric>, nil] per-column widths; nil lets Excel auto-size
      def self.write_table(sheet, styles, headers:, rows:, widths: nil)
        # Row index (0-based) where the header row will land; used to build the
        # table range after the rows are added.
        start_index = sheet.rows.size

        header_styles = Array.new(headers.length, styles[:header])
        sheet.add_row headers, style: header_styles

        body_styles = Array.new(headers.length, styles[:body])
        rows.each do |row|
          sheet.add_row row, style: body_styles
        end

        sheet.column_widths(*widths) if widths

        apply_table(sheet, start_index, headers.length, rows.size)
      end

      # Turn the just-written header + body rows into an Excel table object so it
      # gets filter dropdowns and structured-table behavior. The table name must
      # be unique workbook-wide; sheet name + starting row guarantees that even
      # for multiple tables on one sheet or one table per sheet across systems.
      def self.apply_table(sheet, start_index, num_cols, num_data_rows)
        # A header-only Excel table (no data rows) is flagged as corrupt by Excel
        # on open, so leave the styled header as plain rows in that case.
        return if num_data_rows.zero?

        first_row = start_index + 1
        last_row = first_row + num_data_rows
        range = "A#{first_row}:#{column_letter(num_cols - 1)}#{last_row}"
        name = "Tbl_#{sheet.name.to_s.gsub(/\W+/, '_')}_#{first_row}"
        sheet.add_table(range, name: name,
          style_info: { name: 'TableStyleMedium2', show_row_stripes: false })
      end

      # Convert a 0-based column index to its spreadsheet letter (0 => A).
      def self.column_letter(index)
        letters = +''
        n = index
        loop do
          letters.prepend(((n % 26) + 65).chr)
          n = n / 26 - 1
          break if n.negative?
        end
        letters
      end

      # Set a single column's width without disturbing the others (column_widths
      # is positional/all-at-once, so this targets one already-created column).
      def self.set_column_width(sheet, index, width)
        info = sheet.column_info[index]
        info.width = width if info
      end

      # Write a bold key/value metadata row (label in col A).
      def self.write_kv_row(sheet, styles, label, value)
        sheet.add_row [label, value], style: [styles[:metadata_label], nil]
      end

      # Write a bold section-title row spanning col A.
      def self.write_section_title(sheet, styles, text)
        sheet.add_row [text], style: [styles[:section_title]]
      end

      # Write the report's "none found" message (#18834). Used instead of a table
      # when there are no rows — also avoids emitting a header-only Excel table,
      # which Excel flags as corrupt on open.
      def self.write_no_entries(sheet, styles, message)
        sheet.add_row [message], style: [styles[:no_entries]]
      end

      # Excel worksheet names cannot exceed 31 chars or contain : \ / ? * [ ].
      def self.sanitize_sheet_name(name)
        name.to_s.gsub(%r{[:\\/?*\[\]]}, ' ').strip[0, 31]
      end
    end
  end
end
