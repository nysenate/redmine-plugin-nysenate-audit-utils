# frozen_string_literal: true

module NysenateAuditUtils
  module RequestCodes
    # Helper methods to make request code mapping available in computed custom field formulas
    module FormulaHelper
      # Get request code for the current issue based on Account Action and Target System fields
      # Can be called from computed custom field formulas without arguments
      # @return [String, nil] The request code or nil if mapping not found
      def request_code
        # Get field IDs from configuration
        account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
        target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id

        return nil unless account_action_field_id && target_system_field_id

        # Get field values from current issue
        account_action_value = custom_field_value(account_action_field_id)
        target_system_value = custom_field_value(target_system_field_id)

        return nil if account_action_value.blank? || target_system_value.blank?

        # Get request code from mapper
        custom_mappings = Setting.plugin_nysenate_audit_utils['request_code_mappings'] || {}
        mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(custom_mappings)
        mapper.get_request_code(account_action_value, target_system_value)
      end

      # Get Account Action and Target System values from a request code
      # @param code [String] The request code (e.g., "USRA", "AIXA")
      # @return [Hash, nil] Hash with :account_action and :target_system keys
      def reverse_request_code(code)
        return nil if code.blank?

        custom_mappings = Setting.plugin_nysenate_audit_utils['request_code_mappings'] || {}
        mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(custom_mappings)
        mapper.get_fields_from_code(code)
      end

      private

      # Helper to get custom field value by field ID
      # @param field_id [Integer] The custom field ID
      # @return [String, nil] The field value
      def custom_field_value(field_id)
        cfv = custom_field_values.find { |v| v.custom_field_id == field_id }
        return nil unless cfv

        # For list fields, get the actual value (not the ID)
        cfv.value
      end
    end

    # Patch Issue model to include formula helper methods
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        include FormulaHelper
      end
    end
  end
end

# Apply patch after initialization to ensure Issue model is loaded
Rails.application.config.after_initialize do
  unless Issue.included_modules.include?(NysenateAuditUtils::RequestCodes::IssuePatch)
    Issue.include NysenateAuditUtils::RequestCodes::IssuePatch
  end
end
