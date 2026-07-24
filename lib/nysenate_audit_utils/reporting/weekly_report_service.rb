# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    class WeeklyReportService
      attr_reader :from_date, :to_date, :errors, :project, :update_type

      # Valid Update Type filters (#18838). Narrow the "tickets updated in the
      # window" set by the kind of activity:
      #   all    - every ticket updated in the window
      #   opened - tickets created in the window
      #   closed - tickets closed in the window
      #   other  - tickets with in-window journal activity that isn't the
      #            creation or the close (a note or some other field change)
      UPDATE_TYPES = %w[all opened closed other].freeze

      def initialize(project: nil, from_date: nil, to_date: nil, update_type: 'all')
        @project = project
        @update_type = UPDATE_TYPES.include?(update_type.to_s) ? update_type.to_s : 'all'

        if from_date && to_date
          @from_date = from_date
          @to_date = to_date
        else
          # Default: previous full week from Sunday 00:00 to Sunday 00:00 (server local time)
          most_recent_sunday = Date.current.beginning_of_week(:sunday).to_time
          @from_date = most_recent_sunday - 7.days
          @to_date = most_recent_sunday
        end

        @errors = []
      end

      # Main entry point - generates the weekly report
      # @return [Array<Hash>, nil] Array of ticket hashes or nil on error
      def generate
        build_report_data
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("WeeklyReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # Check if report generation was successful
      def success?
        @errors.empty?
      end

      private

      def build_report_data
        # Get custom field IDs
        user_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.user_id_field_id
        user_uid_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_uid_field_id')
        user_name_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_name_field_id')
        user_location_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_location_field_id')
        user_type_field_id = NysenateAuditUtils::CustomFieldConfiguration.get_field_id('user_type_field_id')
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        unless user_id_field_id
          @errors << "Employee ID custom field is not configured"
          return []
        end

        # Initialize request code mapper
        request_code_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new

        # Query issues by Update Type over the window, newest activity first.
        issues = issues_for_update_type
          .includes(:status, :custom_values)
          .order(updated_on: :desc)

        # Precompute which trackers expose the User ID field in this project, so
        # the per-issue availability check is an in-memory lookup instead of an
        # N+1 (issue.available_custom_fields hits projects/trackers/custom_fields
        # for every row). :all means the field is for all trackers.
        allowed_tracker_ids = user_id_field_tracker_ids(user_id_field_id)

        # Build report data for each issue, filtering out issues without the User ID field configured
        issues.filter_map do |issue|
          # Skip issues whose tracker doesn't expose the User ID field.
          next unless allowed_tracker_ids == :all || allowed_tracker_ids.include?(issue.tracker_id)

          # Get user ID from custom field (may be blank, that's okay)
          user_id = get_custom_field_value(issue, user_id_field_id)

          # Get user UID from custom field (if configured)
          user_uid = user_uid_field_id ? get_custom_field_value(issue, user_uid_field_id) : nil

          # Get user name from custom field (if configured)
          user_name = user_name_field_id ? get_custom_field_value(issue, user_name_field_id) : nil

          # Get office/location from custom field (if configured)
          office = user_location_field_id ? get_custom_field_value(issue, user_location_field_id) : nil

          # Get user type from custom field (if configured)
          user_type = user_type_field_id ? get_custom_field_value(issue, user_type_field_id) : nil

          # Get request code from Account Action and Target System
          request_code = nil
          if account_action_field_id && target_system_field_id
            account_action = get_custom_field_value(issue, account_action_field_id)
            target_system = get_custom_field_value(issue, target_system_field_id)
            request_code = request_code_mapper.get_request_code(account_action, target_system)
          end

          {
            issue_id: issue.id,
            subject: issue.subject,
            status: issue.status.name,
            user_id: user_id,
            user_uid: user_uid,
            user_name: user_name,
            office: office,
            user_type: user_type,
            request_code: request_code,
            updated_on: issue.updated_on,
            created_on: issue.created_on,
            closed_on: issue.closed_on
          }
        end
      end

      # Trackers (in this project) for which the User ID custom field is
      # available. Returns :all when the field is for all trackers, otherwise a
      # Set of tracker ids. Empty Set means the field isn't enabled here.
      def user_id_field_tracker_ids(user_id_field_id)
        field = CustomField.find_by(id: user_id_field_id, type: 'IssueCustomField')
        return Set.new unless field
        return :all if field.is_for_all?
        return Set.new unless field.project_ids.include?(@project.id)

        field.tracker_ids.to_set
      end

      # Build the base issue scope for the selected Update Type (#18838).
      def issues_for_update_type
        base = Issue.where(project_id: @project.id)

        case @update_type
        when 'opened'
          base.where(created_on: @from_date..@to_date)
        when 'closed'
          base.joins(:status)
              .where(issue_statuses: { is_closed: true })
              .where(closed_on: @from_date..@to_date)
        when 'other'
          base.where(id: other_update_issue_ids)
        else # 'all'
          base.where(updated_on: @from_date..@to_date)
        end
      end

      # Issue ids with in-window journal activity that isn't purely the close
      # (a note, a non-closing status change, or any other field change). Ticket
      # creation produces no journal, so it's naturally excluded.
      def other_update_issue_ids
        closed_status_ids = IssueStatus.where(is_closed: true).pluck(:id).map(&:to_s)

        journals = Journal
          .where(journalized_type: 'Issue', created_on: @from_date..@to_date)
          .where(journalized_id: Issue.where(project_id: @project.id).select(:id))
          .includes(:details)

        journals.select { |journal| other_update_journal?(journal, closed_status_ids) }
                .map(&:journalized_id).uniq
      end

      # A journal counts as an "other update" when it carries a note or any
      # detail beyond a status change into a closed status.
      def other_update_journal?(journal, closed_status_ids)
        return true if journal.notes.present?

        journal.details.any? do |detail|
          !(detail.property == 'attr' &&
            detail.prop_key == 'status_id' &&
            closed_status_ids.include?(detail.value.to_s))
        end
      end

      # Get custom field value from an issue
      # @param issue [Issue] The issue
      # @param field_id [Integer] The custom field ID
      # @return [String, nil] The field value or nil
      def get_custom_field_value(issue, field_id)
        custom_value = issue.custom_values.find { |cv| cv.custom_field_id == field_id }
        custom_value&.value
      end
    end
  end
end
