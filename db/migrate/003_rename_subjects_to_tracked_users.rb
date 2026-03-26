# frozen_string_literal: true

# Migration to rename subjects table and columns to tracked_users terminology
# This migration updates the database schema to use "user" terminology while
# maintaining backward compatibility and data integrity.
class RenameSubjectsToTrackedUsers < ActiveRecord::Migration[6.1]
  def up
    # Rename table
    rename_table :subjects, :tracked_users

    # Rename columns
    rename_column :tracked_users, :subject_type, :user_type
    rename_column :tracked_users, :subject_id, :user_id

    # Drop old indexes
    remove_index :tracked_users, name: 'idx_subject_type_id'
    remove_index :tracked_users, name: 'idx_subject_name'
    remove_index :tracked_users, name: 'idx_subject_status'

    # Create new indexes
    add_index :tracked_users, [:user_type, :user_id], unique: true, name: 'idx_user_type_id'
    add_index :tracked_users, :name, name: 'idx_user_name'
    add_index :tracked_users, :status, name: 'idx_user_status'
  end

  def down
    # Remove new indexes
    remove_index :tracked_users, name: 'idx_user_type_id'
    remove_index :tracked_users, name: 'idx_user_name'
    remove_index :tracked_users, name: 'idx_user_status'

    # Restore old indexes
    add_index :tracked_users, [:user_type, :user_id], unique: true, name: 'idx_subject_type_id'
    add_index :tracked_users, :name, name: 'idx_subject_name'
    add_index :tracked_users, :status, name: 'idx_subject_status'

    # Rename columns back
    rename_column :tracked_users, :user_type, :subject_type
    rename_column :tracked_users, :user_id, :subject_id

    # Rename table back
    rename_table :tracked_users, :subjects
  end
end
