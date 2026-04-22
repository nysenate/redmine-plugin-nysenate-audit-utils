# frozen_string_literal: true

# Migration to convert tracked_user.user_id from V-prefixed strings (V1, V2, ...) to
# integer IDs using a numeric offset scheme (500001, 500002, ...).
# Also converts any stored references in custom_values.
class ConvertVendorIdsToIntegerOffset < ActiveRecord::Migration[7.2]
  OFFSET = 500_000

  def up
    # Step A: Seed the offset setting if not already present
    settings_record = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    if settings_record
      value = settings_record.value || {}
      unless value.key?('tracked_user_id_offset')
        value['tracked_user_id_offset'] = OFFSET
        settings_record.value = value
        settings_record.save!
      end
    end

    # Step B: Convert V-prefix string user_ids to integer offset values.
    # Process in ascending order of the numeric suffix to avoid any transient conflicts.
    select_all(<<~SQL).each do |row|
      SELECT id, user_id FROM tracked_users
      WHERE user_id REGEXP '^V[0-9]+$'
      ORDER BY CAST(SUBSTRING(user_id, 2) AS UNSIGNED) ASC
    SQL
      n = row['user_id'][1..].to_i
      new_id = OFFSET + n
      execute("UPDATE tracked_users SET user_id = '#{new_id}' WHERE id = #{row['id']}")
    end

    # Step C: Drop the composite unique index on (user_type, user_id) and replace with
    # a unique index on user_id alone, since IDs are now globally unique across all types.
    remove_index :tracked_users, name: 'idx_user_type_id'
    change_column :tracked_users, :user_id, :integer, null: false
    add_index :tracked_users, :user_id, unique: true, name: 'idx_tracked_user_id'

    # Step D: Update custom_values that stored the old V-prefixed user IDs.
    # custom_values.value is always a string column, so we update string→string.
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')&.value || {}
    field_id = settings['user_id_field_id'].to_i
    if field_id > 0
      execute(<<~SQL)
        UPDATE custom_values
        SET value = CAST(#{OFFSET} + CAST(SUBSTRING(value, 2) AS UNSIGNED) AS CHAR)
        WHERE custom_field_id = #{field_id}
          AND customized_type = 'Issue'
          AND value REGEXP '^V[0-9]+$'
      SQL
    else
      puts "WARNING: user_id_field_id not configured in plugin settings."
      puts "Tracked user IDs stored in issue custom fields were NOT updated."
      puts "If applicable, update custom_values manually after configuring user_id_field_id."
    end
  end

  def down
    # Restore user_id column to string type
    change_column :tracked_users, :user_id, :string, limit: 100, null: false

    # Convert integer IDs back to V-prefix strings
    select_all(<<~SQL).each do |row|
      SELECT id, user_id FROM tracked_users
      WHERE user_id REGEXP '^[0-9]+$'
      ORDER BY CAST(user_id AS UNSIGNED) ASC
    SQL
      n = row['user_id'].to_i - OFFSET
      old_id = "V#{n}"
      execute("UPDATE tracked_users SET user_id = '#{old_id}' WHERE id = #{row['id']}")
    end

    # Restore the composite unique index
    remove_index :tracked_users, name: 'idx_tracked_user_id'
    add_index :tracked_users, [:user_type, :user_id], unique: true, name: 'idx_user_type_id'

    # Reverse custom_values update
    settings = Setting.find_by(name: 'plugin_nysenate_audit_utils')&.value || {}
    field_id = settings['user_id_field_id'].to_i
    if field_id > 0
      execute(<<~SQL)
        UPDATE custom_values
        SET value = CONCAT('V', CAST(CAST(value AS UNSIGNED) - #{OFFSET} AS CHAR))
        WHERE custom_field_id = #{field_id}
          AND customized_type = 'Issue'
          AND value REGEXP '^[0-9]+$'
          AND CAST(value AS UNSIGNED) > #{OFFSET}
      SQL
    end

    # Remove offset setting if it still equals the default we set
    settings_record = Setting.find_by(name: 'plugin_nysenate_audit_utils')
    if settings_record
      value = settings_record.value || {}
      if value['tracked_user_id_offset'] == OFFSET
        value.delete('tracked_user_id_offset')
        settings_record.value = value
        settings_record.save!
      end
    end
  end
end
