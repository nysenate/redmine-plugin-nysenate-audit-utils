# frozen_string_literal: true

# Add the 'Lock / Unlock' and 'Reset Password' action suffixes introduced after
# migration 006. Because 006 ran only once, instances that already applied it
# never received these newer entries. This migration adds only the missing keys,
# leaving migration 006's legacy defaults and any admin-customised values in
# place.
class SetDefaultRequestCodeMappings < ActiveRecord::Migration[7.2]
  NEW_ACTION_SUFFIXES = {
    'Lock / Unlock' => 'U',
    'Reset Password' => 'U'
  }.freeze

  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    suffixes = value['request_code_action_suffixes'] || {}

    # Existing entries win; only the missing new keys are added.
    value['request_code_action_suffixes'] = NEW_ACTION_SUFFIXES.merge(suffixes)

    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    suffixes = value['request_code_action_suffixes']
    return if suffixes.blank?

    NEW_ACTION_SUFFIXES.each_key { |key| suffixes.delete(key) }
    value['request_code_action_suffixes'] = suffixes

    settings.value = value
    settings.save!
  end
end
