# frozen_string_literal: true

module NysenateAuditUtils
  module Subjects
    # Facade service for subject operations
    # Routes requests to appropriate data source based on subject type
    class SubjectService
      # Valid subject types
      VALID_TYPES = %w[Employee Vendor].freeze

      # Search for subjects matching the query
      # @param query [String] The search term
      # @param type [String] The subject type ('Employee' or 'Vendor')
      # @param limit [Integer] Maximum number of results (default: 20)
      # @param offset [Integer] Number of results to skip (default: 0)
      # @return [Array<Hash>] Array of normalized subject hashes
      # @raise [ArgumentError] If type is invalid
      def search(query, type: 'Employee', limit: 20, offset: 0)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.search(query, limit: limit, offset: offset)
        else
          data_source.search(query, subject_type: type, limit: limit, offset: offset)
        end
      end

      # Find a subject by their ID
      # @param id [String] The subject ID
      # @param type [String] The subject type ('Employee' or 'Vendor')
      # @return [Hash, nil] Normalized subject hash or nil if not found
      # @raise [ArgumentError] If type is invalid
      def find_by_id(id, type: 'Employee')
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.find_by_id(id)
        else
          data_source.find_by_id(id, subject_type: type)
        end
      end

      # Create a new subject
      # @param attributes [Hash] Subject attributes (must include subject_type)
      # @return [Hash] Normalized subject hash
      # @raise [ArgumentError] If type is invalid or missing
      # @raise [RuntimeError] If attempting to create an employee
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def create(attributes)
        type = attributes[:subject_type] || attributes['subject_type']
        raise ArgumentError, 'subject_type is required' unless type

        validate_type!(type)

        data_source = get_data_source(type)
        data_source.create(attributes)
      end

      # Update an existing subject
      # @param id [String] The subject ID
      # @param type [String] The subject type
      # @param attributes [Hash] Subject attributes to update
      # @return [Hash] Normalized subject hash
      # @raise [ArgumentError] If type is invalid
      # @raise [RuntimeError] If attempting to update an employee
      # @raise [ActiveRecord::RecordNotFound] If subject not found
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def update(id, type:, attributes:)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.update(id, attributes)
        else
          data_source.update(id, subject_type: type, attributes: attributes)
        end
      end

      # Delete a subject
      # @param id [String] The subject ID
      # @param type [String] The subject type
      # @return [Boolean] true if deleted successfully
      # @raise [ArgumentError] If type is invalid
      # @raise [RuntimeError] If attempting to delete an employee
      # @raise [ActiveRecord::RecordNotFound] If subject not found
      def delete(id, type:)
        validate_type!(type)

        data_source = get_data_source(type)

        if type == 'Employee'
          data_source.delete(id)
        else
          data_source.delete(id, subject_type: type)
        end
      end

      private

      # Get the appropriate data source for the given subject type
      # @param type [String] The subject type
      # @return [SubjectDataSource] The data source instance
      def get_data_source(type)
        case type
        when 'Employee'
          @employee_data_source ||= EmployeeDataSource.new
        when 'Vendor'
          @database_data_source ||= DatabaseDataSource.new
        else
          raise ArgumentError, "Unknown subject type: #{type}"
        end
      end

      # Validate that the subject type is valid
      # @param type [String] The subject type to validate
      # @raise [ArgumentError] If type is not in VALID_TYPES
      def validate_type!(type)
        return if VALID_TYPES.include?(type)

        raise ArgumentError, "Invalid subject type: #{type}. Valid types: #{VALID_TYPES.join(', ')}"
      end
    end
  end
end
