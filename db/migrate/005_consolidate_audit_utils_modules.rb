# frozen_string_literal: true

# Migration to consolidate four separate audit utils modules into a single module.
# Old modules: audit_utils_reporting, audit_utils_user_autofill,
#              audit_utils_packet_creation, audit_utils_tracked_user_management
# New module: audit_utils
class ConsolidateAuditUtilsModules < ActiveRecord::Migration[7.2]
  def up
    # Get all projects that have any of the old modules enabled
    old_module_names = [
      'audit_utils_reporting',
      'audit_utils_user_autofill',
      'audit_utils_packet_creation',
      'audit_utils_tracked_user_management'
    ]

    # Find all project IDs that have at least one old module
    project_ids = EnabledModule
                  .where(name: old_module_names)
                  .distinct
                  .pluck(:project_id)

    # Remove all old module entries
    EnabledModule.where(name: old_module_names).delete_all

    # Add the new consolidated module for each project that had any old module
    project_ids.each do |project_id|
      EnabledModule.create!(project_id: project_id, name: 'audit_utils')
    end
  end

  def down
    # Revert by replacing consolidated module with all four separate modules
    project_ids = EnabledModule
                  .where(name: 'audit_utils')
                  .pluck(:project_id)

    # Remove consolidated module
    EnabledModule.where(name: 'audit_utils').delete_all

    # Add back all four separate modules for each project
    old_module_names = [
      'audit_utils_reporting',
      'audit_utils_user_autofill',
      'audit_utils_packet_creation',
      'audit_utils_tracked_user_management'
    ]

    project_ids.each do |project_id|
      old_module_names.each do |module_name|
        EnabledModule.create!(project_id: project_id, name: module_name)
      end
    end
  end
end
