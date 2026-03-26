# Load library files explicitly since Rails autoloading doesn't work well with plugin lib directories
require_relative 'lib/nysenate_audit_utils/custom_field_configuration'
require_relative 'lib/nysenate_audit_utils/ess/ess_configuration'
require_relative 'lib/nysenate_audit_utils/ess/ess_api_client'
require_relative 'lib/nysenate_audit_utils/ess/ess_employee_service'
require_relative 'lib/nysenate_audit_utils/ess/ess_status_change_service'
require_relative 'lib/nysenate_audit_utils/users/user_data_source'
require_relative 'lib/nysenate_audit_utils/users/employee_data_source'
require_relative 'lib/nysenate_audit_utils/users/database_data_source'
require_relative 'lib/nysenate_audit_utils/users/user_service'
require_relative 'lib/nysenate_audit_utils/reporting/business_day_helper'
require_relative 'lib/nysenate_audit_utils/reporting/daily_report_service'
require_relative 'lib/nysenate_audit_utils/reporting/csv_generator'
require_relative 'lib/nysenate_audit_utils/account_tracking/account_tracking_service'
require_relative 'lib/nysenate_audit_utils/autofill/employee_mapper'
require_relative 'lib/nysenate_audit_utils/autofill/hooks'
require_relative 'lib/nysenate_audit_utils/request_codes/request_code_mapper'
require_relative 'lib/nysenate_audit_utils/request_codes/formula_helper'

Redmine::Plugin.register :nysenate_audit_utils do
  name 'NYSenate Audit Utils Plugin'
  author 'New York State Senate'
  description 'Audit utilities including ESS integration, reporting, user autofill, and packet creation for audit workflows'
  version '0.1.1'
  url 'https://github.com/nysenate/redmine-plugin-nysenate-audit-utils'
  author_url 'https://github.com/nysenate'

  requires_redmine version_or_higher: '5.0.0'

  # Consolidated project module for all audit utils functionality
  project_module :audit_utils do
    # Reporting permissions
    permission :view_audit_reports, { audit_reports: [:index, :daily, :weekly, :monthly, :triennial] }
    permission :export_audit_reports, { audit_reports: [:export] }

    # User autofill permissions
    permission :use_user_autofill, { user_search: [:search, :field_mappings] }

    # Packet creation permissions
    permission :create_packet, { packet_creation: [:create, :create_multi_packet] }

    # Tracked user management permissions
    permission :manage_tracked_users, { tracked_users: [:index, :new, :create, :edit, :update, :destroy] }
  end

  # Menu items
  menu :project_menu, :audit_reports,
       { controller: 'audit_reports', action: 'index' },
       caption: 'Reports',
       param: :project_id,
       if: Proc.new { |p| p.module_enabled?(:audit_utils) }

  menu :project_menu, :tracked_users,
       { controller: 'tracked_users', action: 'index' },
       caption: 'Manage Tracked Users',
       param: :project_id,
       if: Proc.new { |p| p.module_enabled?(:audit_utils) }

  # Consolidated settings
  settings default: {
    # ESS Integration settings
    'ess_base_url' => '',
    'ess_api_key' => '',
    # Custom Field Configuration - all fields use IDs
    # Set to nil to use autoconfiguration by field name
    'user_type_field_id' => nil,
    'user_id_field_id' => nil,
    'user_name_field_id' => nil,
    'user_email_field_id' => nil,
    'user_phone_field_id' => nil,
    'user_status_field_id' => nil,
    'user_uid_field_id' => nil,
    'user_location_field_id' => nil,
    'account_action_field_id' => nil,
    'target_system_field_id' => nil,
    # Request Code Mapping settings
    'request_code_mappings' => {},      # Custom mappings to override defaults
    # Email Reporting settings
    'report_recipients' => ''            # Comma-separated email addresses for all reports
  }, partial: 'settings/audit_utils_settings'
end

# Load patches and components after plugin initialization
Rails.application.config.after_initialize do
  require File.expand_path('lib/attachments_helper_patch', __dir__)
  require File.expand_path('lib/issue_context_menu_hook', __dir__)
end
