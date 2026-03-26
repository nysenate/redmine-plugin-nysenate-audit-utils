# frozen_string_literal: true

module NysenateAuditUtils
  module Users
    # Data source for locally-stored tracked users (Vendors, etc.)
    # Full CRUD operations via TrackedUser ActiveRecord model
    class DatabaseDataSource < UserDataSource
      # Search for tracked users matching the query
      # @param query [String] The search term
      # @param user_type [String] The type of user to search (e.g., 'Vendor')
      # @param limit [Integer] Maximum number of results (default: 20)
      # @param offset [Integer] Number of results to skip (default: 0)
      # @return [Array<Hash>] Array of normalized user hashes
      def search(query, user_type:, limit: 20, offset: 0)
        tracked_users = TrackedUser.where(user_type: user_type)

        if query.present?
          tracked_users = tracked_users.where(
            'name LIKE ? OR user_id LIKE ? OR email LIKE ?',
            "%#{query}%", "%#{query}%", "%#{query}%"
          )
        end

        tracked_users = tracked_users.limit(limit).offset(offset).order(:name)

        tracked_users.map { |tracked_user| normalize_user(tracked_user) }
      end

      # Find a tracked user by their ID
      # @param id [String] The user ID (e.g., 'V1', 'V23')
      # @param user_type [String] The type of user (e.g., 'Vendor')
      # @return [Hash, nil] Normalized user hash or nil if not found
      def find_by_id(id, user_type:)
        tracked_user = TrackedUser.find_by(user_id: id, user_type: user_type)
        return nil unless tracked_user

        normalize_user(tracked_user)
      end

      # Create a new tracked user
      # @param attributes [Hash] User attributes (user_type, user_id, name, etc.)
      # @return [Hash] Normalized user hash
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def create(attributes)
        tracked_user = TrackedUser.new(attributes)
        tracked_user.save!

        normalize_user(tracked_user)
      end

      # Update an existing tracked user
      # @param id [String] The user ID
      # @param user_type [String] The type of user
      # @param attributes [Hash] User attributes to update
      # @return [Hash] Normalized user hash
      # @raise [ActiveRecord::RecordNotFound] If user not found
      # @raise [ActiveRecord::RecordInvalid] If validation fails
      def update(id, user_type:, attributes:)
        tracked_user = TrackedUser.find_by!(user_id: id, user_type: user_type)
        tracked_user.update!(attributes)

        normalize_user(tracked_user)
      end

      # Delete a tracked user
      # @param id [String] The user ID
      # @param user_type [String] The type of user
      # @return [Boolean] true if deleted successfully
      # @raise [ActiveRecord::RecordNotFound] If user not found
      def delete(id, user_type:)
        tracked_user = TrackedUser.find_by!(user_id: id, user_type: user_type)
        tracked_user.destroy!

        true
      end
    end
  end
end
