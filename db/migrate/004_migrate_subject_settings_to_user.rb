# frozen_string_literal: true

# Migration to rename plugin settings from subject_* to user_* terminology
# This migration updates the plugin configuration keys to reflect the user
# terminology while preserving all existing field ID mappings.
class MigrateSubjectSettingsToUser < ActiveRecord::Migration[6.1]
  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

    # Migrate setting keys from subject_* to user_*
    value['user_id_field_id'] = value.delete('subject_id_field_id') if value['subject_id_field_id']
    value['user_name_field_id'] = value.delete('subject_name_field_id') if value['subject_name_field_id']
    value['user_email_field_id'] = value.delete('subject_email_field_id') if value['subject_email_field_id']
    value['user_phone_field_id'] = value.delete('subject_phone_field_id') if value['subject_phone_field_id']
    value['user_status_field_id'] = value.delete('subject_status_field_id') if value['subject_status_field_id']
    value['user_uid_field_id'] = value.delete('subject_uid_field_id') if value['subject_uid_field_id']
    value['user_location_field_id'] = value.delete('subject_location_field_id') if value['subject_location_field_id']
    value['user_type_field_id'] = value.delete('subject_type_field_id') if value['subject_type_field_id']

    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

    # Revert keys back to subject_* terminology
    value['subject_id_field_id'] = value.delete('user_id_field_id') if value['user_id_field_id']
    value['subject_name_field_id'] = value.delete('user_name_field_id') if value['user_name_field_id']
    value['subject_email_field_id'] = value.delete('user_email_field_id') if value['user_email_field_id']
    value['subject_phone_field_id'] = value.delete('user_phone_field_id') if value['user_phone_field_id']
    value['subject_status_field_id'] = value.delete('user_status_field_id') if value['user_status_field_id']
    value['subject_uid_field_id'] = value.delete('user_uid_field_id') if value['user_uid_field_id']
    value['subject_location_field_id'] = value.delete('user_location_field_id') if value['user_location_field_id']
    value['subject_type_field_id'] = value.delete('user_type_field_id') if value['user_type_field_id']

    settings.value = value
    settings.save!
  end
end
