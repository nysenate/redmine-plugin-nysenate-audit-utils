# frozen_string_literal: true

require 'csv'

module NysenateAuditUtils
  module Reporting
    # Formats a UserInfoAuditService::Result as a CSV with metadata header,
    # an Unresolved Tickets table (first, since unresolved tickets are the
    # highest priority for operators), and then a Changes table.
    class UserInfoAuditCsvGenerator
      def self.generate(result, project:, dry_run:, generated_at: Time.now)
        CSV.generate do |csv|
          write_header(csv, project, result.summary, dry_run, generated_at)
          csv << []
          write_unresolved(csv, result.exceptions)
          csv << []
          write_changes(csv, result.changes)
        end
      end

      def self.write_header(csv, project, summary, dry_run, generated_at)
        unresolved = summary[:unresolved_tickets].to_i
        csv << ['Report Name', 'Account Holder Info Audit']
        csv << ['Project', project.identifier]
        csv << ['Generated at', generated_at.strftime('%Y-%m-%d %H:%M:%S %Z')]
        csv << ['Mode', dry_run ? 'Dry run (no changes applied)' : 'Apply']
        csv << ['Total Tickets Scanned', summary[:tickets_scanned].to_i]
        csv << [
          "Unresolved tickets#{unresolved.positive? ? ' (review needed)' : ''}",
          unresolved
        ]
        csv << ['Total Account Holders checked', summary[:account_holders_checked].to_i]
        csv << ['Account Holders with changes', summary[:pairs_with_changes].to_i]
        csv << ['Field updates', summary[:field_updates].to_i]
        csv << [dry_run ? 'Tickets to update' : 'Tickets updated', summary[:tickets_updated].to_i]
        by_category = summary[:unresolved_by_category]
        return if by_category.blank?

        csv << ['Unresolved Tickets by category']
        by_category.each do |category, count|
          csv << [category, count]
        end
      end

      def self.write_unresolved(csv, exceptions)
        csv << ['Unresolved Tickets']
        csv << [
          'Issue ID',
          'Subject',
          'Account Holder Type',
          'Account Holder ID',
          'Account Holder Name',
          'Category',
          'Message'
        ]
        exceptions.each do |row|
          csv << [
            row[:issue_id],
            row[:subject],
            row[:user_type],
            row[:user_id],
            row[:account_holder_name],
            row[:category],
            row[:message]
          ]
        end
      end

      def self.write_changes(csv, changes)
        csv << ['Changes']
        csv << [
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
        changes.each do |row|
          csv << [
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
      end
    end
  end
end
