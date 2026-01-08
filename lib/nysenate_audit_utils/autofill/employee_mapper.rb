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
            name: employee.display_name,
            email: employee.email,
            phone: employee.work_phone,
            status: employee.active ? 'Active' : 'Inactive',
            uid: employee.uid,
            office: employee.resp_center_head&.short_name,
            resp_center_head: employee.resp_center_head
          }
        end
      end
    end
  end
end
