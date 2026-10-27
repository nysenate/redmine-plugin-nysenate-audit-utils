# frozen_string_literal: true

# Seed the default office => GeneralFormInfoID rows for the Quarterly / Annual
# audit export. The init.rb default only applies when the plugin has no saved
# settings, so existing instances need it added here. A saved value (including
# an emptied list) is left in place.
class SetDefaultGeneralFormInfoIdMappings < ActiveRecord::Migration[7.2]
  SETTING_KEY = 'general_form_info_id_mappings'

  DEFAULT_ROWS = [
    { 'id' => '6', 'offices' => 'MOSUPPLY' },
    { 'id' => '8', 'offices' => 'MOPURCHASE' },
    { 'id' => '9', 'offices' => 'MODOCOORD' },
    { 'id' => '10', 'offices' => 'MOFURNISH, MOMAINTAIN, MORECEIVE, MOSHOP, MOINVREC' },
    { 'id' => '11', 'offices' => 'FOACCOUNTS' },
    { 'id' => '12', 'offices' => 'FISCAL, FOPAYROLL' },
    { 'id' => '13', 'offices' => 'PERSONNEL' },
    { 'id' => '14', 'offices' => 'MAJSENIOR, SECOFSEN' }
  ].freeze

  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}
    return if value.key?(SETTING_KEY)

    value[SETTING_KEY] = DEFAULT_ROWS
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
