# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Sets "Selected for Audit" on the tickets picked in the Triennial Audit
    # Report ("Flag Selected").
    #
    # The user needs to both view and edit every ticket submitted; if any
    # fails that check nothing is flagged (the report disables those
    # checkboxes, so this only trips on a stale page or a forged request).
    # Beyond that, only tickets from a configured Triennial source can be
    # flagged. Each change is journaled as the
    # current user with notifications suppressed (same as
    # UserInfoAuditService), and saved without validation so an old ticket
    # missing some unrelated required field can still be flagged.
    class TriennialAuditFlagService
      NOT_SELECTED = TriennialAuditReportService::NOT_SELECTED

      attr_reader :flagged, :unchanged, :failed

      # True when the permission check rejected the submission (nothing flagged).
      def permission_denied?
        @permission_denied
      end

      # @param user [User] journal author
      def initialize(user: User.current)
        @user = user
        @flagged = []
        @unchanged = []
        @failed = []
      end

      # Values offered by the year selector: every audit year, then "No" to
      # clear a mistaken flag.
      # @return [Array<String>]
      def self.flag_values
        field = CustomFieldConfiguration.selected_for_audit_field
        return [] unless field

        years = field.possible_values - [NOT_SELECTED]
        field.possible_values.include?(NOT_SELECTED) ? years + [NOT_SELECTED] : years
      end

      # Default year selection: the current year if it's an option, else the
      # latest year.
      # @return [String, nil]
      def self.default_value
        values = flag_values - [NOT_SELECTED]
        values.include?(Date.current.year.to_s) ? Date.current.year.to_s : values.last
      end

      # @param issue_ids [Array<#to_i>]
      # @param value [String] one of .flag_values
      # @return [self] with #flagged / #unchanged (issue ids) and #failed
      #   ([{ issue_id:, message: }]) populated
      # @raise [ArgumentError] when the field isn't configured or value isn't allowed
      def flag(issue_ids, value)
        field = CustomFieldConfiguration.selected_for_audit_field
        raise ArgumentError, 'The Selected for Audit field is not configured.' unless field
        raise ArgumentError, "\"#{value}\" is not a Selected for Audit value." unless self.class.flag_values.include?(value)

        ids = Array(issue_ids).map(&:to_i).uniq
        issues = Issue.where(id: ids).includes(:project, :tracker, :custom_values).index_by(&:id)
        @failed = permission_failures(ids, issues)
        @permission_denied = @failed.any?
        return self if @permission_denied

        ids.each do |id|
          issue = issues[id]
          if TriennialAuditConfiguration.source_for(issue).nil?
            @failed << { issue_id: id, message: 'not in a Triennial Audit source' }
          elsif !issue.available_custom_fields.include?(field)
            @failed << { issue_id: id, message: "#{field.name} is not enabled for " \
                                                "#{issue.project.name} / #{issue.tracker.name}" }
          else
            flag_issue(issue, field, value)
          end
        end
        self
      end

      private

      # Tickets the user can't view and edit. Missing and invisible tickets
      # get the same message, so the response doesn't reveal which exist.
      def permission_failures(ids, issues)
        ids.filter_map do |id|
          issue = issues[id]
          if issue.nil? || !issue.visible?(@user)
            { issue_id: id, message: "ticket not found or you don't have permission to view it" }
          elsif !issue.attributes_editable?(@user)
            { issue_id: id, message: "you don't have permission to edit it" }
          end
        end
      end

      def flag_issue(issue, field, value)
        if issue.custom_field_value(field) == value
          @unchanged << issue.id
          return
        end

        journal = issue.init_journal(@user)
        journal.notify = false
        issue.custom_field_values = { field.id.to_s => value }
        raise ActiveRecord::RecordNotSaved, issue.errors.full_messages.join('; ') unless issue.save(validate: false)

        @flagged << issue.id
      rescue StandardError => e
        Rails.logger.error("TriennialAuditFlagService failed to flag ##{issue.id}: #{e.message}")
        @failed << { issue_id: issue.id, message: e.message }
      end
    end
  end
end
