# frozen_string_literal: true

module NysenateAuditUtils
  module Users
    # Abstract base class for user data sources
    # Defines the common interface that all data sources must implement
    class UserDataSource
      # Search for users matching the query
      # @param query [String] The search term
      # @return [Array<Hash>] Array of normalized user hashes
      def search(query)
        raise NotImplementedError, "#{self.class.name} must implement #search"
      end

      # Find a user by their ID
      # @param id [String] The user ID
      # @return [Hash, nil] Normalized user hash or nil if not found
      def find_by_id(id)
        raise NotImplementedError, "#{self.class.name} must implement #find_by_id"
      end

      # Create a new user
      # @param attributes [Hash] User attributes
      # @return [Hash] Normalized user hash
      def create(attributes)
        raise NotImplementedError, "#{self.class.name} must implement #create"
      end

      # Update an existing user
      # @param id [String] The user ID
      # @param attributes [Hash] User attributes to update
      # @return [Hash] Normalized user hash
      def update(id, attributes)
        raise NotImplementedError, "#{self.class.name} must implement #update"
      end

      # Delete a user
      # @param id [String] The user ID
      # @return [Boolean] true if deleted successfully
      def delete(id)
        raise NotImplementedError, "#{self.class.name} must implement #delete"
      end

      protected

      # Normalize a tracked user into standard hash format
      # @param tracked_user [Object] The tracked user object (EssEmployee, TrackedUser, etc.)
      # @return [Hash] Normalized user hash with standard keys
      def normalize_user(tracked_user)
        {
          user_type: tracked_user.user_type,
          user_id: tracked_user.user_id,
          name: tracked_user.name,
          email: tracked_user.email,
          phone: tracked_user.phone,
          uid: tracked_user.uid,
          location: tracked_user.location,
          status: tracked_user.status
        }
      end
    end
  end
end
