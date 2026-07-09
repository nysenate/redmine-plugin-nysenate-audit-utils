# frozen_string_literal: true

module NysenateAuditUtils
  module Autofill
    # Maps employee data from ESS to format suitable for Redmine custom fields
    class EmployeeMapper
      class << self
        # Map employee data to field values
        # @param employee [EssEmployee] The employee object from ESS
        # @return [Hash] Hash mapping field purpose symbols to employee values
        def map_employee(employee)
          {
            employee_id: employee.employee_id,
            name: employee.formatted_name,
            email: employee.email,
            phone: employee.work_phone,
            status: employee.active ? 'Active' : 'Inactive',
            uid: employee.uid,
            location: employee.resp_center_head&.code,
            resp_center_head: employee.resp_center_head
          }
        end

        # Map employee data to a { custom_field_id => value } hash suitable for
        # seeding a new-issue form (e.g. issue[custom_field_values][<id>]=<value>).
        # Only includes fields that are actually configured; the daily report is
        # always for employees, so Account Holder Type is fixed to 'Employee'.
        # @param employee [EssEmployee] The employee object from ESS
        # @return [Hash{Integer => Object}] Hash of custom field ID => value
        def map_employee_to_field_values(employee)
          mapped = map_employee(employee)
          field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

          values = {}
          values[field_ids[:user_id]]       = mapped[:employee_id] if field_ids[:user_id]
          values[field_ids[:user_name]]     = mapped[:name]        if field_ids[:user_name]
          values[field_ids[:user_email]]    = mapped[:email]       if field_ids[:user_email]
          values[field_ids[:user_phone]]    = mapped[:phone]       if field_ids[:user_phone]
          values[field_ids[:user_status]]   = mapped[:status]      if field_ids[:user_status]
          values[field_ids[:user_uid]]      = mapped[:uid]         if field_ids[:user_uid]
          values[field_ids[:user_location]] = mapped[:location]    if field_ids[:user_location]
          values[field_ids[:user_type]]     = 'Employee'           if field_ids[:user_type]
          values
        end

        # Map employee data plus removal-specific fields to a { custom_field_id => value }
        # hash for an access-removal ticket: the Account Holder fields, plus Target System
        # set to the system being removed and Account Action fixed to 'Delete'.
        # @param employee [EssEmployee] The employee object from ESS
        # @param target_system [String] The Target System custom field value to remove
        # @return [Hash{Integer => Object}] Hash of custom field ID => value
        def map_removal_field_values(employee, target_system:)
          values = map_employee_to_field_values(employee)
          target_system_field_id = NysenateAuditUtils::CustomFieldConfiguration.target_system_field_id
          account_action_field_id = NysenateAuditUtils::CustomFieldConfiguration.account_action_field_id
          values[target_system_field_id]  = target_system if target_system_field_id
          values[account_action_field_id] = 'Delete'      if account_action_field_id
          values
        end
      end
    end
  end
end
