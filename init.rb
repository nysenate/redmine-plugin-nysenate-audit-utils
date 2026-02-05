# Load library files explicitly since Rails autoloading doesn't work well with plugin lib directories
require_relative 'lib/nysenate_audit_utils/custom_field_configuration'
require_relative 'lib/nysenate_audit_utils/ess/ess_configuration'
require_relative 'lib/nysenate_audit_utils/ess/ess_api_client'
require_relative 'lib/nysenate_audit_utils/ess/ess_employee_service'
require_relative 'lib/nysenate_audit_utils/ess/ess_status_change_service'
require_relative 'lib/nysenate_audit_utils/reporting/business_day_helper'
require_relative 'lib/nysenate_audit_utils/reporting/daily_report_service'
require_relative 'lib/nysenate_audit_utils/account_tracking/account_tracking_service'
require_relative 'lib/nysenate_audit_utils/autofill/employee_mapper'
require_relative 'lib/nysenate_audit_utils/autofill/hooks'
require_relative 'lib/nysenate_audit_utils/request_codes/request_code_mapper'
require_relative 'lib/nysenate_audit_utils/request_codes/formula_helper'

Redmine::Plugin.register :nysenate_audit_utils do
  name 'NYSenate Audit Utils Plugin'
  author 'New York State Senate'
  description 'Audit utilities including ESS integration, reporting, employee autofill, and packet creation for audit workflows'
  version '2.0.0'
  url 'https://github.com/nysenate/redmine-plugin-nysenate-audit-utils'
  author_url 'https://github.com/nysenate'

  requires_redmine version_or_higher: '5.0.0'

  # Project module for reporting functionality
  project_module :audit_utils_reporting do
    permission :view_audit_reports, { audit_reports: [:index, :daily, :weekly, :monthly, :triennial] }
    permission :export_audit_reports, { audit_reports: [:export] }
  end

  # Project module for autofill functionality
  project_module :audit_utils_employee_autofill do
    permission :use_employee_autofill, { employee_search: [:search, :field_mappings] }
  end

  # Project module for packet creation
  project_module :audit_utils_packet_creation do
    permission :create_packet, { packet_creation: [:create, :create_multi_packet] }
  end

  # Menu items
  menu :project_menu, :audit_reports,
       { controller: 'audit_reports', action: 'index' },
       caption: 'Reports',
       param: :project_id,
       if: Proc.new { |p| p.module_enabled?(:audit_utils_reporting) }

  # Consolidated settings
  settings default: {
    # ESS Integration settings
    'ess_base_url' => '',
    'ess_api_key' => '',
    # Custom Field Configuration - all fields use IDs
    # Set to nil to use autoconfiguration by field name
    'employee_id_field_id' => nil,
    'employee_name_field_id' => nil,
    'employee_email_field_id' => nil,
    'employee_phone_field_id' => nil,
    'employee_status_field_id' => nil,
    'employee_uid_field_id' => nil,
    'employee_office_field_id' => nil,
    'account_action_field_id' => nil,
    'target_system_field_id' => nil,
    # Request Code Mapping settings
    'request_code_mappings' => {}      # Custom mappings to override defaults
  }, partial: 'settings/audit_utils_settings'
end

# Load patches and components after plugin initialization
Rails.application.config.after_initialize do
  require File.expand_path('lib/attachments_helper_patch', __dir__)
  require File.expand_path('lib/issue_context_menu_hook', __dir__)
end
