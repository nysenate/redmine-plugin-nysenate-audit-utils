# frozen_string_literal: true

module NysenateAuditUtils
  # Maps an Account Holder's office (the Account Holder Location value) to the
  # GeneralFormInfoID filled into the Quarterly / Annual (SFMS / SFS) audit
  # export. Settings-backed list of rows, mirroring TriennialAuditConfiguration.
  #
  # One row per ID (string keys, as stored in Setting):
  #   'id'      => String - numeric GeneralFormInfoID
  #   'offices' => String - comma-separated office values sharing that ID
  #
  # Offices match case-insensitively on the whole (trimmed) value. An office
  # with no row resolves to nil, leaving the export cell blank.
  class GeneralFormInfoIdConfiguration
    SETTING_KEY = 'general_form_info_id_mappings'

    DEFAULT_ROWS = [
      { 'id' => '6', 'offices' => 'MOSUPPLY' },
      { 'id' => '8', 'offices' => 'MOPURCHASE' },
      { 'id' => '9', 'offices' => 'MODOCOORD' },
      { 'id' => '10', 'offices' => 'MOFURNISH, MOMAINTAIN, MORECEIVE, MOSHOP, MOINVREC' },
      { 'id' => '11', 'offices' => 'FOACCOUNTS' },
      { 'id' => '12', 'offices' => 'FISCAL, FOPAYROLL' },
      { 'id' => '13', 'offices' => 'PERSONNEL' },
      { 'id' => '14', 'offices' => 'MAJSENIOR, SECOFSEN' }
    ].freeze

    class << self
      # All configured rows (string keys), sorted by numeric ID; rows without a
      # numeric ID go last, keeping their saved order. The settings form submits
      # index-keyed params, which the core plugin settings controller saves as a
      # Hash rather than an Array, so normalize either shape here.
      # @return [Array<Hash>]
      def rows
        raw = Setting.plugin_nysenate_audit_utils[SETTING_KEY]
        list = case raw
               when Hash then raw.values
               when Array then raw
               else []
               end
        list.each_with_index.sort_by do |row, i|
          id = row['id'].to_s.strip
          id.match?(/\A\d+\z/) ? [0, id.to_i, i] : [1, 0, i]
        end.map(&:first)
      end

      # Normalized office => ID lookup built from the rows. Rows without a
      # numeric ID are skipped; an office listed on several rows keeps the
      # first row's ID.
      # @return [Hash{String => Integer}]
      def office_map
        rows.each_with_object({}) do |row, map|
          id = row['id'].to_s.strip
          next unless id.match?(/\A\d+\z/)

          office_list(row['offices']).each { |office| map[office] ||= id.to_i }
        end
      end

      # GeneralFormInfoID for an office value, or nil when unmapped.
      # @param office [String, nil]
      # @param map [Hash] a prebuilt office_map, to avoid rebuilding per row
      # @return [Integer, nil]
      def lookup(office, map = office_map)
        return nil if office.blank?

        map[normalize(office)]
      end

      # Offices that appear on more than one row (only the first row's ID is
      # used), for a settings-page warning.
      # @return [Array<String>]
      def duplicate_offices
        rows.flat_map { |row| office_list(row['offices']) }.tally.select { |_, n| n > 1 }.keys
      end

      private

      def office_list(offices)
        offices.to_s.split(',').map { |office| normalize(office) }.reject(&:empty?).uniq
      end

      def normalize(office)
        office.to_s.strip.upcase
      end
    end
  end
end
