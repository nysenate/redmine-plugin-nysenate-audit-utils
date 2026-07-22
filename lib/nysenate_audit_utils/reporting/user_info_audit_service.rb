# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Audits Account Holder cached custom field values on issues against the
    # authoritative data source (ESS for employees, TrackedUser for others)
    # and optionally writes corrections back to the tickets.
    #
    # Returned `Result` carries:
    #   * `unmatched`  — Array of Hash rows for tickets that could not be
    #                    matched to an account holder (missing/invalid ID,
    #                    lookup failure, save failure, etc.)
    #   * `changes`    — Array of Hash rows describing per-field diffs
    #   * `summary`    — Hash of counters
    #   * `success?`   — false only if configuration is invalid
    class UserInfoAuditService
      # Subset of normalized-user keys that map to issue custom fields we sync.
      # (user_type / user_id are the lookup keys; we do not overwrite them.)
      SYNCED_FIELDS = [:name, :email, :phone, :status, :uid, :location].freeze

      # Maps normalized-user key -> CustomFieldConfiguration setting key.
      FIELD_SETTING_KEYS = {
        name: 'user_name_field_id',
        email: 'user_email_field_id',
        phone: 'user_phone_field_id',
        status: 'user_status_field_id',
        uid: 'user_uid_field_id',
        location: 'user_location_field_id'
      }.freeze

      Result = Struct.new(:changes, :unmatched, :summary, :errors, keyword_init: true) do
        def success?
          errors.empty?
        end
      end

      attr_reader :project, :dry_run

      def initialize(project:, dry_run: false)
        @project = project
        @dry_run = dry_run
      end

      def run
        errors = []
        type_field = CustomFieldConfiguration.user_type_field
        id_field   = CustomFieldConfiguration.user_id_field

        errors << "Account Holder Type custom field is not configured" unless type_field
        errors << "Account Holder ID custom field is not configured"   unless id_field

        synced_fields = SYNCED_FIELDS.each_with_object({}) do |key, h|
          cf = CustomFieldConfiguration.get_field(FIELD_SETTING_KEYS[key])
          h[key] = cf if cf
        end

        missing = SYNCED_FIELDS - synced_fields.keys
        if missing.any?
          errors << "Missing Account Holder custom fields: #{missing.join(', ')}"
        end

        return Result.new(changes: [], unmatched: [], summary: {}, errors: errors) if errors.any?

        tracker_ids = scoped_tracker_ids(type_field, id_field)
        pairs = collect_pairs(type_field.id, id_field.id, synced_fields[:name].id, tracker_ids)

        changes = []
        unmatched = []
        # Account Holders ([type, id] pairs) whose authoritative lookup
        # succeeded — used for the "Total Account Holders checked" counter.
        matched_pairs = []
        user_service = NysenateAuditUtils::Users::UserService.new

        pairs.each do |(user_type, user_id), issue_ids|
          type_blank = user_type.to_s.strip.empty?
          id_blank   = user_id.to_s.strip.empty?

          if type_blank && id_blank
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids,
                                            'missing_user_type_and_id',
                                            'Account Holder Type and ID are both blank'))
            next
          elsif type_blank
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids,
                                            'missing_user_type',
                                            'Account Holder Type is blank'))
            next
          elsif id_blank
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids,
                                            'missing_user_id',
                                            'Account Holder ID is blank'))
            next
          end

          begin
            authoritative = user_service.find_by_id(user_id.to_s, type: user_type.to_s)
          rescue ArgumentError => e
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids, 'invalid_user_type', e.message))
            next
          rescue StandardError => e
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids, 'data_source_error',
                                            "#{e.class}: #{e.message}"))
            next
          end

          unless authoritative
            unmatched.concat(pair_unmatched(user_type, user_id, issue_ids, 'user_not_found',
                                            "No #{user_type} found with ID #{user_id}"))
            next
          end

          matched_pairs << [user_type, user_id]
          reconcile_issues(issue_ids, user_type, user_id, authoritative,
                           synced_fields, changes, unmatched)
        end

        Result.new(
          changes: changes,
          unmatched: unmatched,
          summary: build_summary(pairs, changes, unmatched, matched_pairs),
          errors: []
        )
      end

      private

      # Trackers where BOTH the Account Holder Type and ID fields are enabled.
      # Returns nil when both fields are global (is_for_all), meaning no tracker
      # filter is needed. When one or both fields are tracker-scoped, returns the
      # intersection of their trackers so only tickets that can actually carry
      # both fields are audited.
      def scoped_tracker_ids(type_field, id_field)
        per_field = [type_field, id_field].map do |cf|
          cf.is_for_all? ? :all : cf.tracker_ids
        end
        return nil if per_field.all?(:all)

        per_field.map { |t| t == :all ? Tracker.pluck(:id) : t }.reduce(:&)
      end

      # Returns { [user_type, user_id] => [issue_id, ...] } for in-scope issues in
      # the project. When tracker_ids is non-nil, only issues on those trackers are
      # scanned (see #scoped_tracker_ids); an empty array yields no rows. Tickets
      # missing one or both of the Account Holder Type/ID values are intentionally
      # retained here so the run loop can flag them as unmatched.
      # Also caches per-issue Subject and the ticket's cached Account Holder
      # Name custom value (@issue_subjects / @issue_names) so report rows can be
      # labeled per ticket even when the authoritative lookup fails.
      def collect_pairs(type_field_id, id_field_id, name_field_id, tracker_ids = nil)
        @issue_subjects = {}
        @issue_names = {}
        pairs = Hash.new { |h, k| h[k] = [] }
        # A nil filter means "all trackers"; an empty filter means "no in-scope
        # trackers", so there is nothing to scan.
        return pairs if tracker_ids && tracker_ids.empty?

        type_alias = 'cv_type'
        id_alias   = 'cv_id'
        name_alias = 'cv_name'
        tracker_clause =
          if tracker_ids
            " AND issues.tracker_id IN (#{tracker_ids.map(&:to_i).join(',')})"
          else
            ''
          end
        sql = <<~SQL
          SELECT issues.id           AS issue_id,
                 issues.subject      AS subject,
                 #{type_alias}.value AS user_type,
                 #{id_alias}.value   AS user_id,
                 #{name_alias}.value AS account_holder_name
          FROM issues
          LEFT JOIN custom_values #{type_alias}
            ON #{type_alias}.customized_type = 'Issue'
           AND #{type_alias}.customized_id   = issues.id
           AND #{type_alias}.custom_field_id = #{type_field_id.to_i}
          LEFT JOIN custom_values #{id_alias}
            ON #{id_alias}.customized_type = 'Issue'
           AND #{id_alias}.customized_id   = issues.id
           AND #{id_alias}.custom_field_id = #{id_field_id.to_i}
          LEFT JOIN custom_values #{name_alias}
            ON #{name_alias}.customized_type = 'Issue'
           AND #{name_alias}.customized_id   = issues.id
           AND #{name_alias}.custom_field_id = #{name_field_id.to_i}
          WHERE issues.project_id = #{project.id.to_i}#{tracker_clause}
        SQL

        rows = ActiveRecord::Base.connection.select_all(sql)
        rows.each do |row|
          user_type = row['user_type']
          user_id   = row['user_id']
          issue_id = row['issue_id'].to_i
          pairs[[user_type, user_id]] << issue_id
          @issue_subjects[issue_id] = row['subject']
          @issue_names[issue_id]    = row['account_holder_name']
        end
        pairs
      end

      def reconcile_issues(issue_ids, user_type, user_id, authoritative,
                           synced_fields, changes, unmatched)
        issues = Issue.where(id: issue_ids).preload(:custom_values)

        issues.find_each do |issue|
          updates = {}
          row_diffs = []
          account_holder_name = @issue_names[issue.id]

          synced_fields.each do |key, cf|
            current = issue.custom_value_for(cf)&.value.to_s
            expected = authoritative[key].to_s
            next if normalize(current) == normalize(expected)

            updates[cf.id] = expected
            row_diffs << {
              issue_id: issue.id,
              subject: issue.subject,
              user_type: user_type,
              user_id: user_id,
              account_holder_name: account_holder_name,
              field: cf.name,
              old_value: current,
              new_value: expected,
              applied: !dry_run
            }
          end

          next if row_diffs.empty?

          if dry_run
            changes.concat(row_diffs)
            next
          end

          begin
            journal = issue.init_journal(
              journal_author,
              'Account Holder info reconciled by audit_account_holder_info script'
            )
            # Record the journal but skip email notification to watchers —
            # we don't want every reconciliation to ping the whole watcher
            # list. The journal still appears in History / Property Changes.
            journal.notify = false if journal.respond_to?(:notify=)
            issue.custom_field_values = updates
            saved = issue.save(validate: false)
            unless saved
              raise ActiveRecord::RecordNotSaved,
                    issue.errors.full_messages.join('; ')
            end
            changes.concat(row_diffs)
          rescue StandardError => e
            unmatched << {
              issue_id: issue.id,
              subject: issue.subject,
              user_type: user_type,
              user_id: user_id,
              account_holder_name: @issue_names[issue.id],
              category: 'issue_save_failed',
              message: "#{e.class}: #{e.message}"
            }
          end
        end
      end

      # Expands a pair-level (Account Holder Type/ID) lookup failure into one
      # unmatched row per affected ticket, so the report lists unmatched tickets
      # per ticket just like the changes table. Account Holder Name is sourced
      # from the ticket's cached custom value (the authoritative record is
      # unavailable for these failures).
      def pair_unmatched(user_type, user_id, issue_ids, category, message)
        Array(issue_ids).map do |issue_id|
          {
            issue_id: issue_id,
            subject: @issue_subjects[issue_id],
            user_type: user_type,
            user_id: user_id,
            account_holder_name: @issue_names[issue_id],
            category: category,
            message: message
          }
        end
      end

      def normalize(value)
        value.to_s.strip
      end

      # Journal author for the reconciliation entries. Prefer a real
      # authenticated user (User.current) so the History view shows who
      # triggered the run; fall back to the anonymous user when invoked
      # from a rake task with no current user set.
      def journal_author
        @journal_author ||= begin
          current = User.current
          current && current.logged? ? current : User.anonymous
        end
      end

      def build_summary(pairs, changes, unmatched, matched_pairs)
        # Count unmatched tickets per category. Unmatched rows are one per
        # ticket; dedupe by issue_id per category to be safe.
        category_issue_ids = Hash.new { |h, k| h[k] = [] }
        unmatched.each do |row|
          category_issue_ids[row[:category]] << row[:issue_id]
        end
        category_counts = category_issue_ids.transform_values { |ids| ids.uniq.size }
        {
          tickets_scanned: pairs.values.flatten.uniq.size,
          unmatched_tickets: unmatched.pluck(:issue_id).uniq.size,
          account_holders_checked: matched_pairs.uniq.size,
          pairs_with_changes: changes.map { |c| [c[:user_type], c[:user_id]] }.uniq.size,
          field_updates: changes.size,
          tickets_updated: changes.pluck(:issue_id).uniq.size,
          unmatched_by_category: category_counts
        }
      end
    end
  end
end
