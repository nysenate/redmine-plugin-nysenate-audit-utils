# frozen_string_literal: true

module NysenateAuditUtils
  module Users
    # Data source for employees from ESS API
    # Read-only wrapper around EssEmployeeService
    class EmployeeDataSource < UserDataSource
      # Search for employees matching the query
      # @param query [String] The search term
      # @param limit [Integer] Maximum number of results (default: 20)
      # @param offset [Integer] Number of results to skip (default: 0)
      # @return [Array<Hash>] Array of normalized employee hashes
      def search(query, limit: 20, offset: 0)
        employees = NysenateAuditUtils::Ess::EssEmployeeService.search(
          query,
          limit: limit,
          offset: offset
        )

        employees.map { |employee| normalize_employee(employee) }
      end

      # Find an employee by their ID
      # @param id [String, Integer] The employee ID
      # @return [Hash, nil] Normalized employee hash or nil if not found
      def find_by_id(id)
        employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(id)
        return nil unless employee

        normalize_employee(employee)
      end

      # Employees cannot be created via this interface (ESS API only)
      # @raise [RuntimeError] Always raises an error
      def create(attributes)
        raise 'Employees cannot be created locally. They are managed via ESS API.'
      end

      # Employees cannot be updated via this interface (ESS API only)
      # @raise [RuntimeError] Always raises an error
      def update(id, attributes)
        raise 'Employees cannot be updated locally. They are managed via ESS API.'
      end

      # Employees cannot be deleted via this interface (ESS API only)
      # @raise [RuntimeError] Always raises an error
      def delete(id)
        raise 'Employees cannot be deleted locally. They are managed via ESS API.'
      end

      private

      # Normalize an EssEmployee object to standard user hash format
      # @param employee [EssEmployee] The employee object from ESS API
      # @return [Hash] Normalized user hash
      def normalize_employee(employee)
        {
          user_type: 'Employee',
          user_id: employee.employee_id.to_s,
          name: employee.full_name,
          email: employee.email,
          phone: employee.work_phone,
          uid: employee.uid,
          location: employee.location&.display_name,
          status: employee.active ? 'Active' : 'Inactive'
        }
      end
    end
  end
end
