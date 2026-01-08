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
end
