# frozen_string_literal: true

# The SFMS Quarterly / SFS Annual auditors' request codes distinguish the
# "S" entries -- Reset Password and Lock / Unlock -- from the regular Update
# actions. Migrations 006/008 seeded both to the 'U' (update) suffix, producing
# codes like USRU/SFSU. This migration overrides them to 'S' so they render as
# USRS/SFSS, matching the auditors' spreadsheet convention.
#
# Unlike migration 008 (which preserved any existing value), this migration
# force-sets the two keys: the new 'S' value wins over whatever was configured.
class SetResetAndLockSuffixesToS < ActiveRecord::Migration[7.2]
  OVERRIDE_ACTION_SUFFIXES = {
    'Lock / Unlock' => 'S',
    'Reset Password' => 'S'
  }.freeze

  # Value these keys held before this migration (from migration 008), restored
  # on rollback.
  PREVIOUS_ACTION_SUFFIXES = {
    'Lock / Unlock' => 'U',
    'Reset Password' => 'U'
  }.freeze

  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    suffixes = value['request_code_action_suffixes'] || {}

    # New value wins: force the two keys to 'S'.
    value['request_code_action_suffixes'] = suffixes.merge(OVERRIDE_ACTION_SUFFIXES)

    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    suffixes = value['request_code_action_suffixes']
    return if suffixes.blank?

    value['request_code_action_suffixes'] = suffixes.merge(PREVIOUS_ACTION_SUFFIXES)

    settings.value = value
    settings.save!
  end
end
