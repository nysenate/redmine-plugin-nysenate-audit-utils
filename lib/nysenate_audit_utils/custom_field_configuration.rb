# frozen_string_literal: true

module NysenateAuditUtils
  # Unified configuration service for managing custom field mappings
  # All BACHelp modules use this service to access custom field IDs
  class CustomFieldConfiguration
    # Field definitions with metadata
    # Structure: { setting_key => { name:, description:, required: } }
    FIELD_DEFINITIONS = {
      'user_type_field_id' => {
        name: 'User Type',
        description: 'User type field (Employee, Vendor, etc.) for multi-type support',
        required: true,
        category: :autofill
      },
      'user_id_field_id' => {
        name: 'User ID',
        description: 'User ID field for reports and tracking',
        required: true,
        category: :reporting
      },
      'user_name_field_id' => {
        name: 'User Name',
        description: 'User name field for autofill',
        required: true,
        category: :autofill
      },
      'user_email_field_id' => {
        name: 'User Email',
        description: 'User email field for autofill',
        required: true,
        category: :autofill
      },
      'user_phone_field_id' => {
        name: 'User Phone',
        description: 'User phone field for autofill',
        required: true,
        category: :autofill
      },
      'user_status_field_id' => {
        name: 'User Status',
        description: 'User status field for autofill',
        required: true,
        category: :autofill
      },
      'user_uid_field_id' => {
        name: 'User UID',
        description: 'User UID field for autofill',
        required: true,
        category: :autofill
      },
      'user_location_field_id' => {
        name: 'User Location',
        description: 'User location field for autofill',
        required: true,
        category: :autofill
      },
      'account_action_field_id' => {
        name: 'Account Action',
        description: 'Account action field for request code mapping',
        required: true,
        category: :request_codes
      },
      'target_system_field_id' => {
        name: 'Target System',
        description: 'Target system field for request code mapping',
        required: true,
        category: :request_codes
      }
    }.freeze

    class << self
      # Get a custom field ID by setting key
      # @param setting_key [String] The setting key (e.g., 'user_id_field_id')
      # @return [Integer, nil] The custom field ID or nil if not configured
      def get_field_id(setting_key)
        field_id = Setting.plugin_nysenate_audit_utils[setting_key]
        field_id.present? ? field_id.to_i : nil
      end

      # Get a custom field by setting key
      # @param setting_key [String] The setting key
      # @return [CustomField, nil] The custom field or nil
      def get_field(setting_key)
        field_id = get_field_id(setting_key)
        return nil unless field_id

        CustomField.find_by(id: field_id, type: 'IssueCustomField')
      end

      # Get all configured field IDs as a hash
      # @return [Hash<String, Integer>] Hash of setting_key => field_id
      def all_field_ids
        FIELD_DEFINITIONS.keys.each_with_object({}) do |key, result|
          field_id = get_field_id(key)
          result[key] = field_id if field_id
        end
      end

      # Autoconfigure a single field by finding it by name
      # @param setting_key [String] The setting key to autoconfigure
      # @return [Boolean] True if field was found and configured
      def autoconfigure_field(setting_key)
        definition = FIELD_DEFINITIONS[setting_key]
        return false unless definition

        field = CustomField.where(
          type: 'IssueCustomField',
          name: definition[:name]
        ).first

        if field
          Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
            setting_key => field.id
          )
          true
        else
          false
        end
      end

      # Autoconfigure all fields by finding them by name
      # @return [Hash] Hash with :configured and :failed arrays of setting keys
      def autoconfigure_all
        configured = []
        failed = []

        FIELD_DEFINITIONS.each_key do |setting_key|
          if autoconfigure_field(setting_key)
            configured << setting_key
          else
            failed << setting_key
          end
        end

        { configured: configured, failed: failed }
      end

      # Validate configuration
      # @return [Array<String>] Array of validation error messages (empty if valid)
      def validate
        errors = []

        FIELD_DEFINITIONS.each do |setting_key, definition|
          next unless definition[:required]

          field = get_field(setting_key)
          unless field
            errors << "Required field '#{definition[:name]}' (#{setting_key}) is not configured"
          end
        end

        errors
      end

      # Check if configuration is valid
      # @return [Boolean] True if all required fields are configured
      def valid?
        validate.empty?
      end

      # Get configuration status for a specific field
      # @param setting_key [String] The setting key
      # @return [Hash] Status hash with :configured, :field_id, :field_name
      def field_status(setting_key)
        definition = FIELD_DEFINITIONS[setting_key]
        return { configured: false, error: 'Unknown field' } unless definition

        field_id = get_field_id(setting_key)
        field = get_field(setting_key)

        {
          configured: field_id.present? && field.present?,
          field_id: field_id,
          field_name: field&.name,
          expected_name: definition[:name],
          required: definition[:required]
        }
      end

      # Get overall configuration status
      # @return [Hash] Status hash with details for each category
      def configuration_status
        by_category = FIELD_DEFINITIONS.group_by { |_k, v| v[:category] }

        status = {}
        by_category.each do |category, fields|
          configured_count = fields.count do |setting_key, _definition|
            get_field_id(setting_key).present?
          end

          status[category] = {
            total: fields.size,
            configured: configured_count,
            complete: configured_count == fields.size
          }
        end

        status
      end

      # Get field definition metadata
      # @param setting_key [String] The setting key
      # @return [Hash, nil] The field definition or nil
      def field_definition(setting_key)
        FIELD_DEFINITIONS[setting_key]
      end

      # Get all field definitions grouped by category
      # @return [Hash] Hash of category => array of [setting_key, definition] pairs
      def fields_by_category
        FIELD_DEFINITIONS.group_by { |_k, v| v[:category] }
      end

      # Helper methods for common field access patterns

      # Get user type field ID
      def user_type_field_id
        get_field_id('user_type_field_id')
      end

      # Get user type field
      def user_type_field
        get_field('user_type_field_id')
      end

      # Get user ID field ID
      def user_id_field_id
        get_field_id('user_id_field_id')
      end

      # Get user ID field
      def user_id_field
        get_field('user_id_field_id')
      end

      # Get account action field ID
      def account_action_field_id
        get_field_id('account_action_field_id')
      end

      # Get account action field
      def account_action_field
        get_field('account_action_field_id')
      end

      # Get target system field ID
      def target_system_field_id
        get_field_id('target_system_field_id')
      end

      # Get target system field
      def target_system_field
        get_field('target_system_field_id')
      end

      # Get all autofill field IDs as a hash
      # @return [Hash<Symbol, Integer>] Hash mapping field purpose to field ID
      # Example: { user_type: 123, user_id: 124, ... }
      def autofill_field_ids
        {
          user_type: get_field_id('user_type_field_id'),
          user_id: get_field_id('user_id_field_id'),
          user_name: get_field_id('user_name_field_id'),
          user_email: get_field_id('user_email_field_id'),
          user_phone: get_field_id('user_phone_field_id'),
          user_status: get_field_id('user_status_field_id'),
          user_uid: get_field_id('user_uid_field_id'),
          user_location: get_field_id('user_location_field_id')
        }.compact
      end
    end
  end
end
