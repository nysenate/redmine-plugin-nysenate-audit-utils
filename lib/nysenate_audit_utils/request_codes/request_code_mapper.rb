# frozen_string_literal: true

module NysenateAuditUtils
  module RequestCodes
    # Provides bidirectional mapping between Account Action + Target System fields
    # and BACHelp request type codes
    class RequestCodeMapper
      # Default request code mappings based on BACHelp Request Type Definition Chart
      # Structure: { 'Target System' => { 'Account Action' => 'CODE' } }
      DEFAULT_MAPPINGS = {
        'Oracle / SFMS' => {
          'Add' => 'USRA',
          'Delete' => 'USRI',
          'Update Account & Privileges' => 'USRU',
          'Update Privileges Only' => 'USRU',
          'Update Account Only' => 'USRU'
        },
        'AIX' => {
          'Add' => 'AIXA',
          'Delete' => 'AIXI',
          'Update Account & Privileges' => 'AIXU',
          'Update Privileges Only' => 'AIXU',
          'Update Account Only' => 'AIXU'
        },
        'SFS' => {
          'Add' => 'SFSA',
          'Delete' => 'SFSI',
          'Update Account & Privileges' => 'SFSU',
          'Update Privileges Only' => 'SFSU',
          'Update Account Only' => 'SFSU'
        },
        'NYSDS' => {
          'Add' => 'DSA',
          'Delete' => 'DSI',
          'Update Account & Privileges' => 'DSU',
          'Update Privileges Only' => 'DSU',
          'Update Account Only' => 'DSU'
        },
        'PayServ' => {
          'Add' => 'PYSA',
          'Delete' => 'PYSI',
          'Update Account & Privileges' => 'PYSU',
          'Update Privileges Only' => 'PYSU',
          'Update Account Only' => 'PYSU'
        },
        'OGS Swiper Access' => {
          'Add' => 'CTRA',
          'Delete' => 'CTRI'
        }
      }.freeze

      def initialize(custom_mappings = {})
        @mappings = DEFAULT_MAPPINGS.deep_merge(custom_mappings)
        @reverse_mappings = build_reverse_mappings
      end

      # Get request code from Account Action and Target System values
      # @param account_action [String] The account action value (e.g., "Add", "Delete")
      # @param target_system [String] The target system value (e.g., "Oracle / SFMS", "AIX")
      # @return [String, nil] The request code or nil if no mapping exists
      def get_request_code(account_action, target_system)
        return nil if account_action.blank? || target_system.blank?

        @mappings.dig(target_system, account_action)
      end

      # Get Account Action and Target System from request code
      # @param request_code [String] The request code (e.g., "USRA", "AIXA")
      # @return [Hash, nil] Hash with :account_action and :target_system keys, or nil if not found
      def get_fields_from_code(request_code)
        return nil if request_code.blank?

        @reverse_mappings[request_code]
      end

      # Get all available request codes
      # @return [Array<String>] Array of all request codes
      def all_codes
        @reverse_mappings.keys.sort
      end

      # Get all target systems
      # @return [Array<String>] Array of all target systems
      def all_target_systems
        @mappings.keys.sort
      end

      # Get all account actions for a specific target system
      # @param target_system [String] The target system
      # @return [Array<String>] Array of account actions
      def account_actions_for_system(target_system)
        return [] if target_system.blank?

        (@mappings[target_system] || {}).keys.sort
      end

      private

      # Build reverse mapping from request codes to field values
      # When multiple field combinations map to the same code, stores the first found
      def build_reverse_mappings
        reverse = {}
        @mappings.each do |target_system, actions|
          actions.each do |account_action, code|
            # Only store first occurrence if code already exists
            next if reverse.key?(code)

            reverse[code] = {
              account_action: account_action,
              target_system: target_system
            }
          end
        end
        reverse
      end
    end
  end
end
