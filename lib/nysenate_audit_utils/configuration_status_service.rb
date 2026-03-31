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

        # Collect all errors and warnings
        all_errors = []
        all_errors += ess_status[:errors] if ess_status[:errors].any?
        all_errors += custom_fields_status[:errors] if custom_fields_status[:errors].any?
        all_errors += email_status[:errors] if email_status[:errors].any?

        all_warnings = []
        all_warnings += ess_status[:warnings] if ess_status[:warnings].any?
        all_warnings += custom_fields_status[:warnings] if custom_fields_status[:warnings].any?
        all_warnings += email_status[:warnings] if email_status[:warnings].any?

        {
          sections: {
            ess_api: ess_status,
            custom_fields: custom_fields_status,
            email_reporting: email_status
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
