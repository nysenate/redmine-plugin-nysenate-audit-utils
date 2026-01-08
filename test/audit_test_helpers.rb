# frozen_string_literal: true

module AuditTestHelpers
  # Configure nysenate_audit_utils plugin settings with field IDs
  # This is a common pattern across many tests
  #
  # @param options [Hash] Configuration options
  # @option options [Integer] :employee_id_field_id Employee ID field ID
  # @option options [Integer] :employee_name_field_id Employee Name field ID
  # @option options [Integer] :employee_email_field_id Employee Email field ID
  # @option options [Integer] :employee_phone_field_id Employee Phone field ID
  # @option options [Integer] :employee_office_field_id Employee Office field ID
  # @option options [Integer] :employee_status_field_id Employee Status field ID
  # @option options [Integer] :employee_uid_field_id Employee UID field ID
  # @option options [Integer] :account_action_field_id Account Action field ID
  # @option options [Integer] :target_system_field_id Target System field ID
  def configure_audit_fields(options = {})
    settings = {}

    options.each do |key, value|
      settings[key.to_s] = value.to_s if value
    end

    Setting.plugin_nysenate_audit_utils = settings
  end

  # Create or find a custom field for testing
  # @param name [String] Field name
  # @param format [String] Field format (string, list, int, etc.)
  # @param possible_values [Array<String>] Possible values for list fields
  # @return [CustomField] The created or found custom field
  def create_or_find_field(name, format = 'string', possible_values = [])
    field = CustomField.find_by(name: name, type: 'IssueCustomField')

    # If field exists, ensure it's configured for all and update if needed
    if field
      field.update!(is_for_all: true) unless field.is_for_all
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

    IssueCustomField.create!(field_params)
  end

  # Setup standard BACHelp custom fields with IDs configured
  # This is the most common setup pattern across tests
  #
  # @return [Hash] Hash of field name symbols to CustomField objects
  def setup_standard_bachelp_fields
    fields = {
      employee_id: create_or_find_field('Employee ID', 'string'),
      employee_name: create_or_find_field('Employee Name', 'string'),
      employee_email: create_or_find_field('Employee Email', 'string'),
      employee_phone: create_or_find_field('Employee Phone', 'string'),
      employee_office: create_or_find_field('Employee Office', 'string'),
      employee_status: create_or_find_field('Employee Status', 'string'),
      employee_uid: create_or_find_field('Employee UID', 'string'),
      account_action: create_or_find_field('Account Action', 'list',
        ['Add', 'Delete', 'Update Account & Privileges', 'Update Privileges Only', 'Update Account Only']),
      target_system: create_or_find_field('Target System', 'list',
        ['Oracle / SFMS', 'AIX', 'SFS', 'NYSDS', 'PayServ', 'OGS Swiper Access'])
    }

    configure_audit_fields(
      employee_id_field_id: fields[:employee_id].id,
      employee_name_field_id: fields[:employee_name].id,
      employee_email_field_id: fields[:employee_email].id,
      employee_phone_field_id: fields[:employee_phone].id,
      employee_office_field_id: fields[:employee_office].id,
      employee_status_field_id: fields[:employee_status].id,
      employee_uid_field_id: fields[:employee_uid].id,
      account_action_field_id: fields[:account_action].id,
      target_system_field_id: fields[:target_system].id
    )

    fields
  end

  # Clear all Audit Utils configuration
  # Useful for teardown or when testing unconfigured state
  def clear_audit_configuration
    Setting.plugin_nysenate_audit_utils = {}
  end
end
