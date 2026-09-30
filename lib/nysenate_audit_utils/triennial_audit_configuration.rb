# frozen_string_literal: true

module NysenateAuditUtils
  # Configuration for the Triennial Audit Report's cross-project/tracker
  # source list and per-source request-code resolution. Mirrors
  # CustomFieldConfiguration's settings-backed style, but for a list of rows
  # instead of a single field id per key.
  #
  # One row per (project, tracker) pair (string keys, as stored in Setting):
  #   'project_id'   => Integer
  #   'tracker_id'   => Integer
  #   'mapping_mode' => 'tracker' | 'field' | 'account_request_code'
  #   'code'         => String  - 'tracker' mode: one code for every ticket
  #   'field_id'     => Integer - 'field' mode: List custom field to map
  #   'value_codes'  => Hash    - 'field' mode: field value => code
  #
  # 'account_request_code' resolves via RequestCodeMapper (Account Action +
  # Target System). A ticket whose value has no mapped code resolves to nil.
  class TriennialAuditConfiguration
    MAPPING_MODES = %w[tracker field account_request_code].freeze

    class << self
      # All configured source rows, as stored (string keys). The settings
      # form submits index-keyed params (settings[triennial_audit_sources][0][...]),
      # which the core plugin settings controller saves as a Hash rather than
      # an Array, so normalize either shape here.
      # @return [Array<Hash>]
      def sources
        raw = Setting.plugin_nysenate_audit_utils['triennial_audit_sources']
        case raw
        when Hash then raw.values
        when Array then raw
        else []
        end
      end

      # Replace the full source list.
      # @param rows [Array<Hash>]
      def sources=(rows)
        Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
          'triennial_audit_sources' => rows
        )
      end

      # Distinct (project_id, tracker_id) pairs across all source rows, used
      # to drive the report's per-source issue queries.
      # @return [Array<Array(Integer, Integer)>]
      def source_pairs
        sources.filter_map do |row|
          next if row['project_id'].blank? || row['tracker_id'].blank?

          [row['project_id'].to_i, row['tracker_id'].to_i]
        end.uniq
      end

      # "Project / Tracker" display label for a source pair, tolerating a
      # deleted project or tracker.
      # @return [String]
      def source_label(project_id, tracker_id)
        "#{Project.find_by(id: project_id)&.name || "project ##{project_id}"} / " \
          "#{Tracker.find_by(id: tracker_id)&.name || "tracker ##{tracker_id}"}"
      end

      # Source row for an issue's (project, tracker), or nil.
      # @param issue [Issue]
      # @return [Hash, nil]
      def source_for(issue)
        sources.find do |row|
          row['project_id'].to_i == issue.project_id && row['tracker_id'].to_i == issue.tracker_id
        end
      end

      # Resolve the request code for an issue. Returns nil when no row
      # matches or the row can't produce a code, so the ticket still shows
      # in the report with a blank code rather than being dropped.
      # @param issue [Issue]
      # @return [String, nil]
      def resolve_code(issue)
        row = source_for(issue)
        return nil unless row

        case row['mapping_mode']
        when 'tracker'
          row['code'].presence
        when 'field'
          code_via_field(row, issue)
        when 'account_request_code'
          code_via_request_code_mapper(issue)
        end
      end

      # Custom fields a ticket in this project/tracker actually carries
      # (same rule as Issue#available_custom_fields).
      # @return [Array<IssueCustomField>]
      def available_fields(project, tracker)
        return [] unless project && tracker

        project.all_issue_custom_fields & tracker.custom_fields
      end

      # List fields selectable for 'field' mode on this project/tracker.
      # @return [Array<IssueCustomField>]
      def available_list_fields(project, tracker)
        available_fields(project, tracker).select { |f| f.field_format == 'list' }
      end

      # 'account_request_code' mode needs the configured Account Action and
      # Target System fields to be enabled on this project/tracker.
      # @return [Boolean]
      def account_request_code_available?(project, tracker)
        required = [CustomFieldConfiguration.account_action_field_id,
                    CustomFieldConfiguration.target_system_field_id]
        return false if required.any?(&:nil?)

        (required - available_fields(project, tracker).map(&:id)).empty?
      end

      # Rows set to 'account_request_code' whose project/tracker lacks the
      # Account Action / Target System fields (e.g. a field was disabled
      # after the row was saved).
      # @return [Array<Hash>]
      def unavailable_account_request_code_sources
        sources.select do |row|
          next false unless row['mapping_mode'] == 'account_request_code'

          project = Project.find_by(id: row['project_id'])
          tracker = Tracker.find_by(id: row['tracker_id'])
          !account_request_code_available?(project, tracker)
        end
      end

      # Whether the Selected for Audit field is configured but not enabled on
      # this project/tracker, so the report's Flag Selected can't set it.
      # False when the field isn't configured — the Custom Field
      # Configuration section covers that.
      # @return [Boolean]
      def selected_for_audit_missing?(project, tracker)
        field_id = CustomFieldConfiguration.selected_for_audit_field_id
        return false unless field_id

        available_fields(project, tracker).map(&:id).exclude?(field_id)
      end

      # Rows whose project/tracker doesn't have Selected for Audit enabled
      # (rows for a deleted project/tracker are skipped).
      # @return [Array<Hash>]
      def sources_missing_selected_for_audit
        sources.select do |row|
          project = Project.find_by(id: row['project_id'])
          tracker = Tracker.find_by(id: row['tracker_id'])
          project && tracker && selected_for_audit_missing?(project, tracker)
        end
      end

      # Seed a row for the Account Request tracker, on the first of its
      # projects that has Account Action / Target System enabled, unless
      # that pair is already configured. Other project/tracker pairs need
      # explicit admin setup.
      # @return [Boolean] true if a row was added
      def autoconfigure_account_request!
        tracker = Tracker.find_by(name: 'Account Request')
        project = tracker&.projects&.find { |p| account_request_code_available?(p, tracker) }
        return false unless tracker && project

        already_configured = sources.any? do |row|
          row['project_id'].to_i == project.id && row['tracker_id'].to_i == tracker.id
        end
        return false if already_configured

        self.sources = sources + [{
          'project_id' => project.id,
          'tracker_id' => tracker.id,
          'mapping_mode' => 'account_request_code'
        }]
        true
      end

      private

      def code_via_field(row, issue)
        return nil if row['field_id'].blank?

        value = get_custom_field_value(issue, row['field_id'].to_i)
        return nil if value.blank?

        (row['value_codes'] || {})[value].presence
      end

      def code_via_request_code_mapper(issue)
        account_action_field_id = CustomFieldConfiguration.account_action_field_id
        target_system_field_id = CustomFieldConfiguration.target_system_field_id
        return nil unless account_action_field_id && target_system_field_id

        account_action = get_custom_field_value(issue, account_action_field_id)
        target_system = get_custom_field_value(issue, target_system_field_id)
        NysenateAuditUtils::RequestCodes::RequestCodeMapper.new.get_request_code(account_action, target_system)
      end

      def get_custom_field_value(issue, field_id)
        custom_value = issue.custom_values.find { |cv| cv.custom_field_id == field_id }
        custom_value&.value
      end
    end
  end
end
