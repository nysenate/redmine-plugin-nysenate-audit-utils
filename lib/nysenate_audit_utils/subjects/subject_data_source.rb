# frozen_string_literal: true

module NysenateAuditUtils
  module Subjects
    # Abstract base class for subject data sources
    # Defines the common interface that all data sources must implement
    class SubjectDataSource
      # Search for subjects matching the query
      # @param query [String] The search term
      # @return [Array<Hash>] Array of normalized subject hashes
      def search(query)
        raise NotImplementedError, "#{self.class.name} must implement #search"
      end

      # Find a subject by their ID
      # @param id [String] The subject ID
      # @return [Hash, nil] Normalized subject hash or nil if not found
      def find_by_id(id)
        raise NotImplementedError, "#{self.class.name} must implement #find_by_id"
      end

      # Create a new subject
      # @param attributes [Hash] Subject attributes
      # @return [Hash] Normalized subject hash
      def create(attributes)
        raise NotImplementedError, "#{self.class.name} must implement #create"
      end

      # Update an existing subject
      # @param id [String] The subject ID
      # @param attributes [Hash] Subject attributes to update
      # @return [Hash] Normalized subject hash
      def update(id, attributes)
        raise NotImplementedError, "#{self.class.name} must implement #update"
      end

      # Delete a subject
      # @param id [String] The subject ID
      # @return [Boolean] true if deleted successfully
      def delete(id)
        raise NotImplementedError, "#{self.class.name} must implement #delete"
      end

      protected

      # Normalize a subject into standard hash format
      # @param subject [Object] The subject object (EssEmployee, Subject, etc.)
      # @return [Hash] Normalized subject hash with standard keys
      def normalize_subject(subject)
        {
          subject_type: subject.subject_type,
          subject_id: subject.subject_id,
          name: subject.name,
          email: subject.email,
          phone: subject.phone,
          uid: subject.uid,
          location: subject.location,
          status: subject.status
        }
      end
    end
  end
end
