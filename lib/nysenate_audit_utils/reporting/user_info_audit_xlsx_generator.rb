# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Formatted Excel equivalent of UserInfoAuditCsvGenerator: a metadata header,
    # an Unmatched Tickets table (first, as unmatched tickets are the highest
    # priority for operators), then a Changes table — all on one worksheet.
    class UserInfoAuditXlsxGenerator
      def self.generate(result, project:, dry_run:, generated_at: Time.now)
        XlsxGenerator.build_package do |wb, styles|
          wb.add_worksheet(name: 'Account Holder Info Audit') do |sheet|
            write_header(sheet, styles, project, result.summary, dry_run, generated_at)
            sheet.add_row []
            write_unmatched(sheet, styles, result.unmatched)
            sheet.add_row []
            write_changes(sheet, styles, result.changes)
            # The tables set column A narrow (Issue ID); widen it so the summary
            # stat labels in the header section are readable (labels also wrap).
            XlsxGenerator.set_column_width(sheet, 0, 34)
          end
        end
      end

      def self.write_header(sheet, styles, project, summary, dry_run, generated_at)
        unmatched = summary[:unmatched_tickets].to_i
        XlsxGenerator.write_kv_row(sheet, styles, 'Report Name', 'Account Holder Info Audit')
        XlsxGenerator.write_kv_row(sheet, styles, 'Project', project.identifier)
        XlsxGenerator.write_kv_row(sheet, styles, 'Generated at', generated_at.strftime('%Y-%m-%d %H:%M:%S %Z'))
        XlsxGenerator.write_kv_row(sheet, styles, 'Mode', dry_run ? 'Dry run (no changes applied)' : 'Apply')
        XlsxGenerator.write_kv_row(sheet, styles, 'Total Tickets Scanned', summary[:tickets_scanned].to_i)
        XlsxGenerator.write_kv_row(sheet, styles,
          "Unmatched tickets#{unmatched.positive? ? ' (review needed)' : ''}", unmatched)
        XlsxGenerator.write_kv_row(sheet, styles, 'Total Account Holders checked', summary[:account_holders_checked].to_i)
        XlsxGenerator.write_kv_row(sheet, styles, 'Account Holders with changes', summary[:pairs_with_changes].to_i)
        XlsxGenerator.write_kv_row(sheet, styles, 'Field updates', summary[:field_updates].to_i)
        XlsxGenerator.write_kv_row(sheet, styles,
          dry_run ? 'Tickets to update' : 'Tickets updated', summary[:tickets_updated].to_i)

        by_category = summary[:unmatched_by_category]
        return if by_category.blank?

        XlsxGenerator.write_kv_row(sheet, styles, 'Unmatched Tickets by category', nil)
        by_category.each do |category, count|
          XlsxGenerator.write_kv_row(sheet, styles, category, count)
        end
      end

      def self.write_unmatched(sheet, styles, unmatched)
        XlsxGenerator.write_section_title(sheet, styles, 'Unmatched Tickets')
        headers = [
          'Issue ID',
          'Subject',
          'Account Holder Type',
          'Account Holder ID',
          'Account Holder Name',
          'Category',
          'Message'
        ]
        rows = unmatched.map do |row|
          [
            row[:issue_id],
            row[:subject],
            row[:user_type],
            row[:user_id],
            row[:account_holder_name],
            row[:category],
            row[:message]
          ]
        end
        XlsxGenerator.write_table(sheet, styles,
          headers: headers,
          rows: rows,
          widths: [10, 40, 16, 14, 24, 18, 40]
        )
      end

      def self.write_changes(sheet, styles, changes)
        XlsxGenerator.write_section_title(sheet, styles, 'Changes')
        headers = [
          'Issue ID',
          'Subject',
          'Account Holder Type',
          'Account Holder ID',
          'Account Holder Name',
          'Account Holder Field',
          'Old Value',
          'New Value',
          'Applied'
        ]
        rows = changes.map do |row|
          [
            row[:issue_id],
            row[:subject],
            row[:user_type],
            row[:user_id],
            row[:account_holder_name],
            row[:field],
            row[:old_value],
            row[:new_value],
            row[:applied] ? 'yes' : 'no'
          ]
        end
        XlsxGenerator.write_table(sheet, styles,
          headers: headers,
          rows: rows,
          widths: [10, 40, 16, 14, 24, 20, 20, 20, 10]
        )
      end
    end
  end
end
