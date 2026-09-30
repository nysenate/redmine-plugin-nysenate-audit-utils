# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Builds the Triennial Audit Report: every ticket opened in a date window
    # across the project/tracker pairs configured in TriennialAuditConfiguration.
    #
    # Not project-scoped: the report covers every configured source. It is
    # all-or-nothing for the viewer — if they can't see every ticket in the
    # window, #permission_errors lists the missing permissions and the caller
    # shows those instead of a partial report. Each source is queried on its
    # own, so a failure (e.g. a deleted project) is recorded in #errors and
    # the other sources still render.
    #
    # Rows are flat; grouping by request code is left to the presentation
    # layer (see .group_by_code).
    class TriennialAuditReportService
      # Code filter value for tickets whose request code didn't resolve.
      NO_CODE = '__none__'
      # Selected for Audit value meaning "not selected". Tickets with no value
      # set filter as this too.
      NOT_SELECTED = 'No'

      attr_reader :from_date, :to_date, :errors, :permission_errors

      # @param from_date [Time, Date] start of the Open Date window (inclusive)
      # @param to_date [Time, Date] end of the Open Date window (inclusive)
      # @param user [User] whose issue visibility applies
      def initialize(from_date: nil, to_date: nil, user: User.current)
        @user = user
        window = self.class.default_window
        @from_date = (from_date || window[:from]).beginning_of_day
        @to_date = (to_date || window[:to]).end_of_day
        @errors = []
        @permission_errors = []
      end

      # Trailing three years ending today, inclusive both ends.
      # @return [Hash] { from:, to: }
      def self.default_window
        today = Date.current
        { from: (today - 3.years + 1.day).in_time_zone, to: today.in_time_zone }
      end

      # Sort rows by request code (unresolved codes last), then ticket number,
      # and group them for display: [[code_or_nil, rows], ...].
      # @param rows [Array<Hash>]
      # @return [Array<Array(String, Array<Hash>)>]
      def self.group_by_code(rows)
        sort_rows(rows).chunk_while { |a, b| a[:request_code] == b[:request_code] }
                       .map { |group| [group.first[:request_code], group] }
      end

      # @param rows [Array<Hash>]
      # @return [Array<Hash>]
      def self.sort_rows(rows)
        rows.sort_by { |r| [r[:request_code].nil? ? 1 : 0, r[:request_code].to_s, r[:issue_id]] }
      end

      # "project_id-tracker_id" key identifying a row's source, as used by the
      # report's project/tracker filter.
      # @return [String]
      def self.source_key(row)
        "#{row[:project_id]}-#{row[:tracker_id]}"
      end

      # Code filter value for a row (NO_CODE when unresolved).
      # @return [String]
      def self.code_key(row)
        row[:request_code] || NO_CODE
      end

      # Selected for Audit filter value for a row (NOT_SELECTED when blank).
      # @return [String]
      def self.selected_key(row)
        row[:selected_for_audit] || NOT_SELECTED
      end

      # Apply the report's filters. Blank filters are ignored.
      # @param source [String, nil] a .source_key value
      # @param code [String, nil] a request code, or NO_CODE
      # @param selected [String, nil] a Selected for Audit value; NOT_SELECTED
      #   also matches tickets with no value
      # @param search [String, nil] case-insensitive substring of the code or
      #   subject, or an exact ticket number (a leading '#' is ignored)
      # @return [Array<Hash>]
      def self.filter_rows(rows, source: nil, code: nil, selected: nil, search: nil)
        rows = rows.select { |r| source_key(r) == source } if source.present?
        rows = rows.select { |r| code_key(r) == code } if code.present?
        rows = rows.select { |r| selected_key(r) == selected } if selected.present?
        rows = rows.select { |r| search_match?(r, search) } if search.present?
        rows
      end

      def self.search_match?(row, search)
        q = search.strip.downcase
        ticket = q.delete_prefix('#')
        return true if ticket.match?(/\A\d+\z/) && row[:issue_id].to_s == ticket

        row[:request_code].to_s.downcase.include?(q) || row[:subject].to_s.downcase.include?(q)
      end
      private_class_method :search_match?

      # @return [Array<Hash>] report rows from every source that could be read
      def generate
        TriennialAuditConfiguration.source_pairs.flat_map do |project_id, tracker_id|
          rows_for_source(project_id, tracker_id)
        end
      end

      def success?
        @errors.empty?
      end

      private

      def rows_for_source(project_id, tracker_id)
        project = Project.find_by(id: project_id)
        tracker = Tracker.find_by(id: tracker_id)
        unless project && tracker
          @errors << "Source #{TriennialAuditConfiguration.source_label(project_id, tracker_id)}: " \
                     "the #{project ? 'tracker' : 'project'} no longer exists."
          return []
        end

        scope = Issue.where(project_id: project.id, tracker_id: tracker.id, created_on: from_date..to_date)
        rows = scope.visible(@user).includes(:status, :custom_values).map { |issue| build_row(issue) }
        check_permissions(project, tracker, scope.count - rows.size)
        rows
      rescue StandardError => e
        Rails.logger.error("TriennialAuditReportService source #{project_id}/#{tracker_id} failed: " \
                           "#{e.message}\n#{e.backtrace.join("\n")}")
        @errors << "Source #{TriennialAuditConfiguration.source_label(project_id, tracker_id)}: #{e.message}"
        []
      end

      # Record which permission keeps the user from seeing the whole source:
      # View issues on the project, View issues for the tracker (per-tracker
      # role permissions), or an Issues visibility setting that hides some
      # tickets (private ones, or everything not their own).
      def check_permissions(project, tracker, hidden_count)
        roles = @user.admin? ? [] : @user.roles_for_project(project).select { |r| r.has_permission?(:view_issues) }
        message =
          if !@user.allowed_to?(:view_issues, project)
            "View issues in #{project.name}"
          elsif !@user.admin? && roles.none? { |r| r.permissions_tracker?(:view_issues, tracker) }
            "View issues for the #{tracker.name} tracker in #{project.name}"
          elsif hidden_count.positive?
            "Issues visibility \"All issues\" in #{project.name} " \
              "(your current visibility hides #{hidden_count} #{tracker.name} #{'ticket'.pluralize(hidden_count)} " \
              'in this date range)'
          end
        # One project can back several sources; list each missing permission once.
        @permission_errors << message if message && @permission_errors.exclude?(message)
      end

      def build_row(issue)
        {
          request_code: TriennialAuditConfiguration.resolve_code(issue),
          subject: issue.subject,
          issue_id: issue.id,
          open_date: issue.created_on,
          closed_date: issue.closed_on,
          status: issue.status&.name,
          selected_for_audit: selected_for_audit(issue),
          # Flag Selected needs edit rights on the ticket (view is a given here).
          editable: issue.attributes_editable?(@user),
          project_id: issue.project_id,
          tracker_id: issue.tracker_id
        }
      end

      def selected_for_audit(issue)
        field_id = CustomFieldConfiguration.selected_for_audit_field_id
        return nil unless field_id

        issue.custom_values.find { |cv| cv.custom_field_id == field_id }&.value.presence
      end
    end
  end
end
