# frozen_string_literal: true

module AuditTestHelpers
  # Configure nysenate_audit_utils plugin settings with field IDs
  # This is a common pattern across many tests
  #
  # @param options [Hash] Configuration options
  # @option options [Integer] :user_type_field_id User Type field ID
  # @option options [Integer] :user_id_field_id User ID field ID
  # @option options [Integer] :user_name_field_id User Name field ID
  # @option options [Integer] :user_email_field_id User Email field ID
  # @option options [Integer] :user_phone_field_id User Phone field ID
  # @option options [Integer] :user_location_field_id User Location field ID
  # @option options [Integer] :user_status_field_id User Status field ID
  # @option options [Integer] :user_uid_field_id User UID field ID
  # @option options [Integer] :account_action_field_id Account Action field ID
  # @option options [Integer] :target_system_field_id Target System field ID
  # @option options [Hash] :request_code_system_prefixes Request code system prefix mappings
  # @option options [Hash] :request_code_action_suffixes Request code action suffix mappings
  def configure_audit_fields(options = {})
    settings = {}

    options.each do |key, value|
      next unless value

      # Keep hashes as hashes, only convert field IDs to strings
      if value.is_a?(Hash)
        settings[key.to_s] = value
      else
        settings[key.to_s] = value.to_s
      end
    end

    Setting.plugin_nysenate_audit_utils = settings
  end

  # Create or find a custom field for testing
  # @param name [String] Field name
  # @param format [String] Field format (string, list, int, etc.)
  # @param possible_values [Array<String>] Possible values for list fields
  # @param tracker [Tracker] Optional tracker to associate with the field
  # @return [CustomField] The created or found custom field
  def create_or_find_field(name, format = 'string', possible_values = [], tracker = nil)
    field = CustomField.find_by(name: name, type: 'IssueCustomField')

    # If field exists, ensure it's configured for all and update if needed
    if field
      field.update!(is_for_all: true) unless field.is_for_all
      # Associate with tracker if provided and not already associated
      if tracker && !tracker.custom_fields.include?(field)
        tracker.custom_fields << field
      end
      return field
    end

    field_params = {
      name: name,
      field_format: format,
      type: 'IssueCustomField',
      is_required: false,
      is_for_all: true
    }

    field_params[:possible_values] = possible_values if format == 'list' && possible_values.any?

    field = IssueCustomField.create!(field_params)

    # Associate with tracker if provided
    if tracker
      tracker.custom_fields << field
    end

    field
  end

  # Setup standard BACHelp custom fields with IDs configured
  # This is the most common setup pattern across tests
  #
  # @param tracker [Tracker] Optional tracker to associate fields with
  # @return [Hash] Hash of field name symbols to CustomField objects
  def setup_standard_bachelp_fields(tracker = nil)
    fields = {
      user_type: create_or_find_field('User Type', 'list', ['Employee', 'Vendor'], tracker),
      user_id: create_or_find_field('User ID', 'string', [], tracker),
      user_name: create_or_find_field('User Name', 'string', [], tracker),
      user_email: create_or_find_field('User Email', 'string', [], tracker),
      user_phone: create_or_find_field('User Phone', 'string', [], tracker),
      user_location: create_or_find_field('User Location', 'string', [], tracker),
      user_status: create_or_find_field('User Status', 'string', [], tracker),
      user_uid: create_or_find_field('User UID', 'string', [], tracker),
      account_action: create_or_find_field('Account Action', 'list',
        ['Add', 'Delete', 'Update Account & Privileges', 'Update Privileges Only', 'Update Account Only'], tracker),
      target_system: create_or_find_field('Target System', 'list',
        ['Oracle / SFMS', 'AIX', 'SFS', 'NYSDS', 'PayServ', 'OGS Swiper Access'], tracker)
    }

    # Setup request code mappings for tests
    request_code_system_prefixes = {
      'Oracle / SFMS' => 'USR',
      'AIX' => 'AIX',
      'SFS' => 'SFS',
      'NYSDS' => 'DS',
      'PayServ' => 'PYS',
      'OGS Swiper Access' => 'CTR'
    }

    request_code_action_suffixes = {
      'Add' => 'A',
      'Delete' => 'I',
      'Update Account & Privileges' => 'U',
      'Update Privileges Only' => 'U',
      'Update Account Only' => 'U'
    }

    configure_audit_fields(
      user_type_field_id: fields[:user_type].id,
      user_id_field_id: fields[:user_id].id,
      user_name_field_id: fields[:user_name].id,
      user_email_field_id: fields[:user_email].id,
      user_phone_field_id: fields[:user_phone].id,
      user_location_field_id: fields[:user_location].id,
      user_status_field_id: fields[:user_status].id,
      user_uid_field_id: fields[:user_uid].id,
      account_action_field_id: fields[:account_action].id,
      target_system_field_id: fields[:target_system].id,
      request_code_system_prefixes: request_code_system_prefixes,
      request_code_action_suffixes: request_code_action_suffixes
    )

    fields
  end

  # Clear all Audit Utils configuration
  # Useful for teardown or when testing unconfigured state
  def clear_audit_configuration
    Setting.plugin_nysenate_audit_utils = {}
  end
end
