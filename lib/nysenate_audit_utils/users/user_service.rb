# frozen_string_literal: true

module NysenateAuditUtils
  module Users
    # Facade service for tracked user operations
    # Routes requests to appropriate data source based on user type
    class UserService
      # Valid user types
      VALID_TYPES = %w[Employee Vendor].freeze

      # Search for tracked users matching the query
      # @param query [String] The search term
      # @param type [String] The user type ('Employee' or 'Vendor')
      # @param limit [Integer] Maximum number of results (default: 20)
      # @param offset [Integer] Number of results to skip (default: 0)
      # @return [Array<Hash>] Array of normalized user hashes
      # @raise [ArgumentError] If type is invalid
      def search(query, type: 'Employee', limit: 20, offset: 0)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.search(query, limit: limit, offset: offset)
        else
          data_source.search(query, user_type: type, limit: limit, offset: offset)
        end
      end

      # Find a tracked user by their ID
      # @param id [String] The user ID
      # @param type [String] The user type ('Employee' or 'Vendor')
      # @return [Hash, nil] Normalized user hash or nil if not found
      # @raise [ArgumentError] If type is invalid
      def find_by_id(id, type: 'Employee')
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.find_by_id(id)
        else
          data_source.find_by_id(id, user_type: type)
        end
      end

      # Create a new tracked user
      # @param attributes [Hash] User attributes (must include user_type)
      # @return [Hash] Normalized user hash
      # @raise [ArgumentError] If type is invalid or missing
      # @raise [RuntimeError] If attempting to create an employee
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def create(attributes)
        type = attributes[:user_type] || attributes['user_type']
        raise ArgumentError, 'user_type is required' unless type

        validate_type!(type)

        data_source = get_data_source(type)
        data_source.create(attributes)
      end

      # Update an existing tracked user
      # @param id [String] The user ID
      # @param type [String] The user type
      # @param attributes [Hash] User attributes to update
      # @return [Hash] Normalized user hash
      # @raise [ArgumentError] If type is invalid
      # @raise [RuntimeError] If attempting to update an employee
      # @raise [ActiveRecord::RecordNotFound] If user not found
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def update(id, type:, attributes:)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.update(id, attributes)
        else
          data_source.update(id, user_type: type, attributes: attributes)
        end
      end

      # Delete a tracked user
      # @param id [String] The user ID
      # @param type [String] The user type
      # @return [Boolean] true if deleted successfully
      # @raise [ArgumentError] If type is invalid
      # @raise [RuntimeError] If attempting to delete an employee
      # @raise [ActiveRecord::RecordNotFound] If user not found
      def delete(id, type:)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.delete(id)
        else
          data_source.delete(id, user_type: type)
        end
      end

      private

      # Get the appropriate data source for the given user type
      # @param type [String] The user type
      # @return [UserDataSource] The data source instance
      def get_data_source(type)
        case type
        when 'Employee'
          @employee_data_source ||= EmployeeDataSource.new
        when 'Vendor'
          @database_data_source ||= DatabaseDataSource.new
        else
          raise ArgumentError, "Unknown user type: #{type}"
        end
      end

      # Validate that the user type is valid
      # @param type [String] The user type to validate
      # @raise [ArgumentError] If type is not in VALID_TYPES
      def validate_type!(type)
        return if VALID_TYPES.include?(type)

        raise ArgumentError, "Invalid user type: #{type}. Valid types: #{VALID_TYPES.join(', ')}"
      end
    end
  end
end
