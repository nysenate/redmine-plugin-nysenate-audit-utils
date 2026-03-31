# frozen_string_literal: true

module NysenateAuditUtils
  # Service for checking configuration status across all sections
  class ConfigurationStatusService
    # Status levels
    STATUS_OK = :ok
    STATUS_WARNING = :warning
    STATUS_ERROR = :error

    class << self
      # Get overall configuration status for all sections
      # @return [Hash] Hash with section statuses and overall status
      def overall_status
        ess_status = ess_api_status
        custom_fields_status = self.custom_fields_status
        email_status = email_reporting_status
        request_codes_status = self.request_codes_status

        # Collect all errors and warnings
        all_errors = []
        all_errors += ess_status[:errors] if ess_status[:errors].any?
        all_errors += custom_fields_status[:errors] if custom_fields_status[:errors].any?
        all_errors += email_status[:errors] if email_status[:errors].any?
        all_errors += request_codes_status[:errors] if request_codes_status[:errors].any?

        all_warnings = []
        all_warnings += ess_status[:warnings] if ess_status[:warnings].any?
        all_warnings += custom_fields_status[:warnings] if custom_fields_status[:warnings].any?
        all_warnings += email_status[:warnings] if email_status[:warnings].any?
        all_warnings += request_codes_status[:warnings] if request_codes_status[:warnings].any?

        {
          sections: {
            ess_api: ess_status,
            custom_fields: custom_fields_status,
            email_reporting: email_status,
            request_codes: request_codes_status
          },
          all_errors: all_errors,
          all_warnings: all_warnings,
          has_issues: all_errors.any? || all_warnings.any?
        }
      end

      # Get ESS API configuration status
      # @return [Hash] Status hash with :status, :errors, :warnings
      def ess_api_status
        errors = NysenateAuditUtils::Ess::EssConfiguration.validation_errors
        valid = NysenateAuditUtils::Ess::EssConfiguration.valid?

        {
          status: valid ? STATUS_OK : STATUS_ERROR,
          valid: valid,
          errors: errors.map { |e| "ESS API: #{e}" },
          warnings: []
        }
      end

      # Get Custom Fields configuration status
      # @return [Hash] Status hash with :status, :errors, :warnings
      def custom_fields_status
        validation_errors = NysenateAuditUtils::CustomFieldConfiguration.validate
        field_definitions = NysenateAuditUtils::CustomFieldConfiguration::FIELD_DEFINITIONS

        # Count configured fields
        configured_count = field_definitions.count do |setting_key, _definition|
          NysenateAuditUtils::CustomFieldConfiguration.get_field_id(setting_key).present?
        end
        total_count = field_definitions.size
        unconfigured_count = total_count - configured_count

        valid = validation_errors.empty?

        # Summarize errors instead of listing each field
        errors = []
        if unconfigured_count > 0
          errors << "Custom Fields: #{unconfigured_count} field#{unconfigured_count > 1 ? 's are' : ' is'} not configured"
        end

        {
          status: valid ? STATUS_OK : STATUS_ERROR,
          valid: valid,
          errors: errors,
          warnings: [],
          configured_count: configured_count,
          total_count: total_count,
          unconfigured_count: unconfigured_count
        }
      end

      # Get Email Reporting configuration status
      # @return [Hash] Status hash with :status, :errors, :warnings
      def email_reporting_status
        recipients = Setting.plugin_nysenate_audit_utils['report_recipients']

        # Email configuration is optional, so we use warnings instead of errors
        warnings = []
        if recipients.blank?
          warnings << "Email Reporting: No default recipients configured. Reports can still be run manually."
        end

        {
          status: warnings.empty? ? STATUS_OK : STATUS_WARNING,
          valid: true, # Email is optional
          errors: [],
          warnings: warnings
        }
      end

      # Get Request Code configuration status
      # @return [Hash] Status hash with :status, :errors, :warnings
      def request_codes_status
        errors = []
        warnings = []

        # Get current custom field values
        account_action_field = NysenateAuditUtils::CustomFieldConfiguration.account_action_field
        target_system_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field

        # If custom fields are not configured, return error
        unless account_action_field && target_system_field
          errors << "Request Codes: Custom fields for Account Action and Target System must be configured first"
          return {
            status: STATUS_ERROR,
            valid: false,
            errors: errors,
            warnings: warnings
          }
        end

        # Get current mappings from settings
        settings = Setting.plugin_nysenate_audit_utils || {}
        system_prefixes = settings['request_code_system_prefixes'] || {}
        action_suffixes = settings['request_code_action_suffixes'] || {}

        # Check for unmapped custom field values (errors)
        unmapped_systems = []
        target_system_field.possible_values.each do |value|
          unmapped_systems << value unless system_prefixes.key?(value)
        end

        unmapped_actions = []
        account_action_field.possible_values.each do |value|
          unmapped_actions << value unless action_suffixes.key?(value)
        end

        if unmapped_systems.any?
          errors << "Request Codes: #{unmapped_systems.size} Target System value#{unmapped_systems.size > 1 ? 's are' : ' is'} not mapped"
        end

        if unmapped_actions.any?
          errors << "Request Codes: #{unmapped_actions.size} Account Action value#{unmapped_actions.size > 1 ? 's are' : ' is'} not mapped"
        end

        # Check for dangling mappings (warnings)
        current_target_systems = target_system_field.possible_values
        dangling_systems = system_prefixes.keys.reject { |k| current_target_systems.include?(k) }

        current_account_actions = account_action_field.possible_values
        dangling_actions = action_suffixes.keys.reject { |k| current_account_actions.include?(k) }

        if dangling_systems.any?
          warnings << "Request Codes: #{dangling_systems.size} Target System mapping#{dangling_systems.size > 1 ? 's exist' : ' exists'} for removed custom field value#{dangling_systems.size > 1 ? 's' : ''}"
        end

        if dangling_actions.any?
          warnings << "Request Codes: #{dangling_actions.size} Account Action mapping#{dangling_actions.size > 1 ? 's exist' : ' exists'} for removed custom field value#{dangling_actions.size > 1 ? 's' : ''}"
        end

        # Determine overall status
        status = if errors.any?
                   STATUS_ERROR
                 elsif warnings.any?
                   STATUS_WARNING
                 else
                   STATUS_OK
                 end

        {
          status: status,
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
          unmapped_systems: unmapped_systems,
          unmapped_actions: unmapped_actions,
          dangling_systems: dangling_systems,
          dangling_actions: dangling_actions
        }
      end

      # Get status badge text for a section
      # @param section_status [Hash] Section status hash
      # @return [String] Badge text ('✓', '⚠', '✗')
      def status_badge(section_status)
        case section_status[:status]
        when STATUS_OK
          '✓'
        when STATUS_WARNING
          '⚠'
        when STATUS_ERROR
          '✗'
        end
      end

      # Get status badge CSS class for a section
      # @param section_status [Hash] Section status hash
      # @return [String] CSS class name
      def status_badge_class(section_status)
        case section_status[:status]
        when STATUS_OK
          'status-ok'
        when STATUS_WARNING
          'status-warning'
        when STATUS_ERROR
          'status-error'
        end
      end

      # Get status description for a section
      # @param section_status [Hash] Section status hash
      # @return [String] Human-readable status description
      def status_description(section_status)
        case section_status[:status]
        when STATUS_OK
          'All configured'
        when STATUS_WARNING
          'Warnings'
        when STATUS_ERROR
          'Configuration required'
        end
      end
    end
  end
end
