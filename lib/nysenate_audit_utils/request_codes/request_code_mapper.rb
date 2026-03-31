# frozen_string_literal: true

module NysenateAuditUtils
  module RequestCodes
    # Provides bidirectional mapping between Account Action + Target System fields
    # and BACHelp request type codes using a simplified prefix-suffix system
    class RequestCodeMapper
      # Default system prefix mappings (fallback if not configured in settings)
      DEFAULT_SYSTEM_PREFIXES = {
        'Oracle / SFMS' => 'USR',
        'AIX' => 'AIX',
        'SFS' => 'SFS',
        'NYSDS' => 'DS',
        'PayServ' => 'PYS',
        'OGS Swiper Access - A42F' => 'AGB',
        'OGS Swiper Access - LB2' => 'CTR',
        'Github' => 'GIT',
        'NYSenate.gov Website' => 'WEB',
        'OnSolve / SendWordNow' => 'ALT',
        'VPN' => 'REM'
      }.freeze

      # Default action suffix mappings (fallback if not configured in settings)
      # Multiple actions may map to the same suffix
      DEFAULT_ACTION_SUFFIXES = {
        'Add' => 'A',
        'Delete' => 'I',
        'Update Account & Privileges' => 'U',
        'Update Privileges Only' => 'U',
        'Update Account Only' => 'U'
      }.freeze

      def initialize(custom_system_prefixes = {}, custom_action_suffixes = {})
        # Load from settings or use defaults
        settings = Setting.plugin_nysenate_audit_utils || {}
        base_system_prefixes = settings['request_code_system_prefixes'] || DEFAULT_SYSTEM_PREFIXES
        base_action_suffixes = settings['request_code_action_suffixes'] || DEFAULT_ACTION_SUFFIXES

        # Merge with any custom overrides
        @system_prefixes = base_system_prefixes.merge(custom_system_prefixes)
        @action_suffixes = base_action_suffixes.merge(custom_action_suffixes)
        @reverse_system_prefixes = build_reverse_system_prefixes
        @reverse_action_suffixes = build_reverse_action_suffixes
        @action_priority_order = nil # Cached action priority from custom field
        @action_priority_cached_at = nil # Timestamp of when priority order was cached
      end

      # Get request code from Account Action and Target System values
      # @param account_action [String] The account action value (e.g., "Add", "Delete")
      # @param target_system [String] The target system value (e.g., "Oracle / SFMS", "AIX")
      # @return [String, nil] The request code or nil if no mapping exists
      def get_request_code(account_action, target_system)
        return nil if account_action.blank? || target_system.blank?

        prefix = @system_prefixes[target_system]
        suffix = @action_suffixes[account_action]

        return nil if prefix.nil? || suffix.nil?

        prefix + suffix
      end

      # Get Account Action and Target System from request code
      # @param request_code [String] The request code (e.g., "USRA", "AIXA")
      # @return [Hash, nil] Hash with :account_action and :target_system keys, or nil if not found
      def get_fields_from_code(request_code)
        return nil if request_code.blank?
        return nil if request_code.length < 2

        # Split into suffix (last character) and prefix (everything else)
        suffix = request_code[-1]
        prefix = request_code[0..-2]

        target_system = @reverse_system_prefixes[prefix]
        return nil if target_system.nil?

        # Get all actions that map to this suffix
        actions = @reverse_action_suffixes[suffix]
        return nil if actions.nil? || actions.empty?

        # If multiple actions map to the same suffix, choose based on field priority order
        account_action = prioritize_action(actions)

        {
          account_action: account_action,
          target_system: target_system
        }
      end

      # Get all available request codes
      # @return [Array<String>] Array of all request codes
      def all_codes
        codes = []
        @system_prefixes.each do |_system, prefix|
          @action_suffixes.values.uniq.each do |suffix|
            codes << prefix + suffix
          end
        end
        codes.sort
      end

      # Get all target systems
      # @return [Array<String>] Array of all target systems
      def all_target_systems
        @system_prefixes.keys.sort
      end

      # Get all account actions for a specific target system
      # @param target_system [String] The target system
      # @return [Array<String>] Array of account actions
      def account_actions_for_system(target_system)
        return [] if target_system.blank?
        return [] unless @system_prefixes.key?(target_system)

        @action_suffixes.keys.sort
      end

      private

      # Build reverse mapping from prefixes to systems
      def build_reverse_system_prefixes
        reverse = {}
        @system_prefixes.each do |system, prefix|
          reverse[prefix] = system
        end
        reverse
      end

      # Build reverse mapping from suffixes to actions
      # Multiple actions may map to the same suffix
      def build_reverse_action_suffixes
        reverse = {}
        @action_suffixes.each do |action, suffix|
          reverse[suffix] ||= []
          reverse[suffix] << action
        end
        reverse
      end

      # Prioritize action from list based on custom field possible_values order
      # @param actions [Array<String>] List of actions that map to same suffix
      # @return [String] The highest priority action
      def prioritize_action(actions)
        return actions.first if actions.size == 1

        # Get cached action priority order
        priority_order = action_priority_order

        # If no priority order available, return first action
        return actions.first unless priority_order

        # Find the first action in possible_values order that exists in our actions list
        priority_order.each do |value|
          return value if actions.include?(value)
        end

        # Fallback to first action if none found in possible_values
        actions.first
      end

      # Get action priority order from custom field (cached for 1 minute)
      # @return [Array<String>, nil] Priority-ordered list of action values
      def action_priority_order
        # Check if cache is valid (less than 1 minute old)
        cache_valid = @action_priority_order &&
                      @action_priority_cached_at &&
                      (Time.now - @action_priority_cached_at) < 60

        return @action_priority_order if cache_valid

        # Fetch and cache the priority order from custom field
        account_action_field = NysenateAuditUtils::CustomFieldConfiguration.account_action_field
        @action_priority_order = account_action_field&.possible_values
        @action_priority_cached_at = Time.now

        @action_priority_order
      end
    end
  end
end
