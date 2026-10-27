# frozen_string_literal: true

# Seed the Triennial Audit Report's Target System whitelist. The setting
# stores Target System values, so the default request-code prefixes are
# resolved to systems through the saved request_code_system_prefixes mapping;
# a prefix with no mapped system is skipped. A saved value (including an
# emptied list) is left in place.
class SetDefaultTriennialTargetSystems < ActiveRecord::Migration[7.2]
  SETTING_KEY = 'triennial_audit_target_systems'
  DEFAULT_PREFIXES = %w[USR AIX SYS OPR CTR AGB REM].freeze

  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    return if value.key?(SETTING_KEY)

    prefixes = value['request_code_system_prefixes'] || {}
    systems = prefixes.select { |_system, prefix| DEFAULT_PREFIXES.include?(prefix) }.keys
    missing = DEFAULT_PREFIXES - prefixes.values
    say "No Target System mapped to #{missing.join(', ')}; skipped." if missing.any?

    value[SETTING_KEY] = systems
    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    value.delete(SETTING_KEY)
    settings.value = value
    settings.save!
  end
end
