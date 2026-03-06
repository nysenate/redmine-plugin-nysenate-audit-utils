# frozen_string_literal: true

module NysenateAuditUtils
  module Subjects
    # Data source for locally-stored subjects (Vendors, etc.)
    # Full CRUD operations via Subject ActiveRecord model
    class DatabaseDataSource < SubjectDataSource
      # Search for subjects matching the query
      # @param query [String] The search term
      # @param subject_type [String] The type of subject to search (e.g., 'Vendor')
      # @param limit [Integer] Maximum number of results (default: 20)
      # @param offset [Integer] Number of results to skip (default: 0)
      # @return [Array<Hash>] Array of normalized subject hashes
      def search(query, subject_type:, limit: 20, offset: 0)
        subjects = Subject.where(subject_type: subject_type)

        if query.present?
          subjects = subjects.where(
            'name LIKE ? OR subject_id LIKE ? OR email LIKE ?',
            "%#{query}%", "%#{query}%", "%#{query}%"
          )
        end

        subjects = subjects.limit(limit).offset(offset).order(:name)

        subjects.map { |subject| normalize_subject(subject) }
      end

      # Find a subject by their ID
      # @param id [String] The subject ID (e.g., 'V1', 'V23')
      # @param subject_type [String] The type of subject (e.g., 'Vendor')
      # @return [Hash, nil] Normalized subject hash or nil if not found
      def find_by_id(id, subject_type:)
        subject = Subject.find_by(subject_id: id, subject_type: subject_type)
        return nil unless subject

        normalize_subject(subject)
      end

      # Create a new subject
      # @param attributes [Hash] Subject attributes (subject_type, subject_id, name, etc.)
      # @return [Hash] Normalized subject hash
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def create(attributes)
        subject = Subject.new(attributes)
        subject.save!

        normalize_subject(subject)
      end

      # Update an existing subject
      # @param id [String] The subject ID
      # @param subject_type [String] The type of subject
      # @param attributes [Hash] Subject attributes to update
      # @return [Hash] Normalized subject hash
      # @raise [ActiveRecord::RecordNotFound] If subject not found
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def update(id, subject_type:, attributes:)
        subject = Subject.find_by!(subject_id: id, subject_type: subject_type)
        subject.update!(attributes)

        normalize_subject(subject)
      end

      # Delete a subject
      # @param id [String] The subject ID
      # @param subject_type [String] The type of subject
      # @return [Boolean] true if deleted successfully
      # @raise [ActiveRecord::RecordNotFound] If subject not found
      def delete(id, subject_type:)
        subject = Subject.find_by!(subject_id: id, subject_type: subject_type)
        subject.destroy!

        true
      end
    end
  end
end
