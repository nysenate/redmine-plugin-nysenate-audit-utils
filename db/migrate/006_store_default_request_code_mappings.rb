# frozen_string_literal: true

# Migration to move request code prefix/suffix mappings from code to database settings
class StoreDefaultRequestCodeMappings < ActiveRecord::Migration[7.2]
  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

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

    # Only set defaults if not already configured
    value['request_code_system_prefixes'] ||= default_system_prefixes
    value['request_code_action_suffixes'] ||= default_action_suffixes

    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

    # Remove the request code mappings from settings
    value.delete('request_code_system_prefixes')
    value.delete('request_code_action_suffixes')

    settings.value = value
    settings.save!
  end
end
