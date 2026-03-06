# frozen_string_literal: true

# Migration to rename plugin settings from employee_* to subject_* terminology
# This migration updates the plugin configuration keys to reflect the broader
# subject-type refactoring while preserving all existing field ID mappings.
class MigrateEmployeeSettingsToSubject < ActiveRecord::Migration[6.1]
  def up
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

    # Migrate setting keys from employee_* to subject_*
    value['subject_id_field_id'] = value.delete('employee_id_field_id') if value['employee_id_field_id']
    value['subject_name_field_id'] = value.delete('employee_name_field_id') if value['employee_name_field_id']
    value['subject_email_field_id'] = value.delete('employee_email_field_id') if value['employee_email_field_id']
    value['subject_phone_field_id'] = value.delete('employee_phone_field_id') if value['employee_phone_field_id']
    value['subject_status_field_id'] = value.delete('employee_status_field_id') if value['employee_status_field_id']
    value['subject_uid_field_id'] = value.delete('employee_uid_field_id') if value['employee_uid_field_id']
    value['subject_location_field_id'] = value.delete('employee_office_field_id') if value['employee_office_field_id']

    settings.value = value
    settings.save!
  end

  def down
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    return unless settings

    value = settings.value || {}

    # Revert keys back to employee_* terminology
    value['employee_id_field_id'] = value.delete('subject_id_field_id') if value['subject_id_field_id']
    value['employee_name_field_id'] = value.delete('subject_name_field_id') if value['subject_name_field_id']
    value['employee_email_field_id'] = value.delete('subject_email_field_id') if value['subject_email_field_id']
    value['employee_phone_field_id'] = value.delete('subject_phone_field_id') if value['subject_phone_field_id']
    value['employee_status_field_id'] = value.delete('subject_status_field_id') if value['subject_status_field_id']
    value['employee_uid_field_id'] = value.delete('subject_uid_field_id') if value['subject_uid_field_id']
    value['employee_office_field_id'] = value.delete('subject_location_field_id') if value['subject_location_field_id']

    settings.value = value
    settings.save!
  end
end
