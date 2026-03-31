# frozen_string_literal: true

# Migration to move request code prefix/suffix mappings from code to database settings
class StoreDefaultRequestCodeMappings < ActiveRecord::Migration[7.2]
  def up
    # Define default system prefix mappings
    default_system_prefixes = {
      'Oracle / SFMS' => 'USR',
      'AIX' => 'AIX',
      'SFS' => 'SFS',
      'NYSDS' => 'DS',
      'PayServ' => 'PYS',
      'OGS Swiper Access - A42F' => 'AGB',
      'OGS Swiper Access - LB2' => 'CTR',
      'Github' => 'GIT',
      'NYSenate.gov Website' => 'WEB',
      'OnSolve / SendWordNow' => 'ALT',
      'VPN' => 'REM'
    }

    # Define default action suffix mappings
    default_action_suffixes = {
      'Add' => 'A',
      'Delete' => 'I',
      'Update Account & Privileges' => 'U',
      'Update Privileges Only' => 'U',
      'Update Account Only' => 'U'
    }

    # Get current settings or initialize empty hash
    settings = Setting.plugin_nysenate_audit_utils || {}

    # Only set defaults if not already configured
    settings['request_code_system_prefixes'] ||= default_system_prefixes
    settings['request_code_action_suffixes'] ||= default_action_suffixes

    # Save back to settings
    Setting.plugin_nysenate_audit_utils = settings
  end

  def down
    # Remove the request code mappings from settings
    settings = Setting.plugin_nysenate_audit_utils || {}
    settings.delete('request_code_system_prefixes')
    settings.delete('request_code_action_suffixes')
    Setting.plugin_nysenate_audit_utils = settings
  end
end
