# frozen_string_literal: true

# Controller for managing Audit Utils plugin settings
# Provides autoconfiguration functionality for custom field mappings
class AuditUtilsSettingsController < ApplicationController
  before_action :require_admin

  # Autoconfigure all custom fields by finding them by name
  # POST /nysenate_audit_utils_settings/autoconfigure_all
  def autoconfigure_all
    result = NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_all

    if result[:failed].empty?
      flash[:notice] = "Successfully autoconfigured #{result[:configured].size} field(s)."
    elsif result[:configured].empty?
      flash[:error] = "Failed to autoconfigure any fields. Please configure them manually."
    else
      flash[:warning] = "Autoconfigured #{result[:configured].size} field(s), but #{result[:failed].size} field(s) could not be found."
    end

    redirect_to plugin_settings_path('nysenate_audit_utils')
  rescue => e
    logger.error "Autoconfiguration error: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred during autoconfiguration: #{e.message}"
    redirect_to plugin_settings_path('nysenate_audit_utils')
  end

  # Autoconfigure a single custom field by finding it by name
  # POST /nysenate_audit_utils_settings/autoconfigure_field
  # Params: setting_key - the field setting key to autoconfigure
  def autoconfigure_field
    setting_key = params[:setting_key]

    if setting_key.blank?
      flash[:error] = "No field specified for autoconfiguration"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    definition = NysenateAuditUtils::CustomFieldConfiguration.field_definition(setting_key)
    unless definition
      flash[:error] = "Unknown field: #{setting_key}"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    if NysenateAuditUtils::CustomFieldConfiguration.autoconfigure_field(setting_key)
      flash[:notice] = "Successfully autoconfigured field '#{definition[:name]}'"
    else
      flash[:error] = "Could not find custom field named '#{definition[:name]}'. Please configure manually."
    end

    redirect_to plugin_settings_path('nysenate_audit_utils')
  rescue => e
    logger.error "Autoconfiguration error: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred during autoconfiguration: #{e.message}"
    redirect_to plugin_settings_path('nysenate_audit_utils')
  end

  # Get autoconfiguration status as JSON
  # GET /nysenate_audit_utils_settings/configuration_status
  def configuration_status
    status = NysenateAuditUtils::CustomFieldConfiguration.configuration_status
    validation_errors = NysenateAuditUtils::CustomFieldConfiguration.validate

    render json: {
      status: status,
      valid: validation_errors.empty?,
      errors: validation_errors
    }
  rescue => e
    logger.error "Configuration status error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  # Delete a dangling request code mapping
  # DELETE /nysenate_audit_utils_settings/delete_dangling_mapping
  # Params: type - 'system' or 'action', value - the mapping key to delete
  def delete_dangling_mapping
    mapping_type = params[:type]
    mapping_value = params[:value]

    if mapping_type.blank? || mapping_value.blank?
      flash[:error] = "Invalid parameters for deleting dangling mapping"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    # Get current settings
    settings = Setting.plugin_nysenate_audit_utils || {}

    # Determine which mapping to modify
    setting_key = case mapping_type
                  when 'system'
                    'request_code_system_prefixes'
                  when 'action'
                    'request_code_action_suffixes'
                  else
                    nil
                  end

    unless setting_key
      flash[:error] = "Invalid mapping type: #{mapping_type}"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    # Get the current mappings
    mappings = settings[setting_key] || {}

    # Delete the dangling mapping
    if mappings.key?(mapping_value)
      mappings.delete(mapping_value)
      settings[setting_key] = mappings
      Setting.plugin_nysenate_audit_utils = settings

      mapping_type_label = mapping_type == 'system' ? 'Target System' : 'Account Action'
      flash[:notice] = "Deleted dangling #{mapping_type_label} mapping for '#{mapping_value}'"
    else
      flash[:warning] = "Mapping not found: #{mapping_value}"
    end

    redirect_to plugin_settings_path('nysenate_audit_utils')
  rescue => e
    logger.error "Delete dangling mapping error: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred while deleting the mapping: #{e.message}"
    redirect_to plugin_settings_path('nysenate_audit_utils')
  end

  # Delete all dangling request code mappings of a specific type
  # DELETE /nysenate_audit_utils_settings/delete_all_dangling_mappings
  # Params: type - 'system' or 'action'
  def delete_all_dangling_mappings
    mapping_type = params[:type]

    if mapping_type.blank?
      flash[:error] = "Invalid parameters for deleting dangling mappings"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    # Determine which mapping to modify
    setting_key = case mapping_type
                  when 'system'
                    'request_code_system_prefixes'
                  when 'action'
                    'request_code_action_suffixes'
                  else
                    nil
                  end

    unless setting_key
      flash[:error] = "Invalid mapping type: #{mapping_type}"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    # Get current status to find dangling mappings
    request_codes_status = NysenateAuditUtils::ConfigurationStatusService.request_codes_status
    dangling_keys = mapping_type == 'system' ? request_codes_status[:dangling_systems] : request_codes_status[:dangling_actions]

    if dangling_keys.empty?
      flash[:warning] = "No dangling mappings found"
      redirect_to plugin_settings_path('nysenate_audit_utils')
      return
    end

    # Get current settings
    settings = Setting.plugin_nysenate_audit_utils || {}
    mappings = settings[setting_key] || {}

    # Delete all dangling mappings
    deleted_count = 0
    dangling_keys.each do |key|
      if mappings.delete(key)
        deleted_count += 1
      end
    end

    settings[setting_key] = mappings
    Setting.plugin_nysenate_audit_utils = settings

    mapping_type_label = mapping_type == 'system' ? 'Target System' : 'Account Action'
    flash[:notice] = "Deleted #{deleted_count} dangling #{mapping_type_label} mapping(s)"

    redirect_to plugin_settings_path('nysenate_audit_utils')
  rescue => e
    logger.error "Delete all dangling mappings error: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred while deleting mappings: #{e.message}"
    redirect_to plugin_settings_path('nysenate_audit_utils')
  end
end
