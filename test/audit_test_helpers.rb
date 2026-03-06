# frozen_string_literal: true

module AuditTestHelpers
  # Configure nysenate_audit_utils plugin settings with field IDs
  # This is a common pattern across many tests
  #
  # @param options [Hash] Configuration options
  # @option options [Integer] :subject_type_field_id Subject Type field ID
  # @option options [Integer] :subject_id_field_id Subject ID field ID
  # @option options [Integer] :subject_name_field_id Subject Name field ID
  # @option options [Integer] :subject_email_field_id Subject Email field ID
  # @option options [Integer] :subject_phone_field_id Subject Phone field ID
  # @option options [Integer] :subject_location_field_id Subject Location field ID
  # @option options [Integer] :subject_status_field_id Subject Status field ID
  # @option options [Integer] :subject_uid_field_id Subject UID field ID
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
      subject_type: create_or_find_field('Subject Type', 'list', ['Employee', 'Vendor'], tracker),
      subject_id: create_or_find_field('Subject ID', 'string', [], tracker),
      subject_name: create_or_find_field('Subject Name', 'string', [], tracker),
      subject_email: create_or_find_field('Subject Email', 'string', [], tracker),
      subject_phone: create_or_find_field('Subject Phone', 'string', [], tracker),
      subject_location: create_or_find_field('Subject Location', 'string', [], tracker),
      subject_status: create_or_find_field('Subject Status', 'string', [], tracker),
      subject_uid: create_or_find_field('Subject UID', 'string', [], tracker),
      account_action: create_or_find_field('Account Action', 'list',
        ['Add', 'Delete', 'Update Account & Privileges', 'Update Privileges Only', 'Update Account Only'], tracker),
      target_system: create_or_find_field('Target System', 'list',
        ['Oracle / SFMS', 'AIX', 'SFS', 'NYSDS', 'PayServ', 'OGS Swiper Access'], tracker)
    }

    configure_audit_fields(
      subject_type_field_id: fields[:subject_type].id,
      subject_id_field_id: fields[:subject_id].id,
      subject_name_field_id: fields[:subject_name].id,
      subject_email_field_id: fields[:subject_email].id,
      subject_phone_field_id: fields[:subject_phone].id,
      subject_location_field_id: fields[:subject_location].id,
      subject_status_field_id: fields[:subject_status].id,
      subject_uid_field_id: fields[:subject_uid].id,
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
