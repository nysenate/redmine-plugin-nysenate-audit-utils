# frozen_string_literal: true

module NysenateAuditUtils
  module Templates
    # Substitutes `<Field Name>` tokens in template subject/description text with
    # the corresponding custom-field values from an issue (feature #18835).
    #
    # A token is replaced only when its inner text exactly matches the name of a
    # custom field on the issue; tokens that match nothing (e.g. `<OSR's ONLY>`,
    # `<existing user (name / userID)>`, `<Reason: ...>`) are left untouched.
    # Interpolation is meant to run AFTER the issue's field values are assigned,
    # so tokens resolve to the final (template + Account Holder) values.
    module FieldInterpolator
      TOKEN = /<([^<>]+)>/

      module_function

      # @param text [String, nil] the template text
      # @param issue [Issue] an issue whose custom_field_values are populated
      # @return [String] text with matched tokens replaced
      def interpolate(text, issue)
        return '' if text.blank?

        values = value_map(issue)
        text.gsub(TOKEN) do |match|
          name = Regexp.last_match(1)
          values.key?(name) ? values[name] : match
        end
      end

      # Build a { custom_field_name => display_string } map from the issue's
      # populated custom field values.
      # @param issue [Issue]
      # @return [Hash{String => String}]
      def value_map(issue)
        issue.custom_field_values.each_with_object({}) do |cfv, map|
          map[cfv.custom_field.name] = formatted(cfv)
        end
      end

      # Render a custom field value as a plain string suitable for a subject or
      # description. User/version fields resolve ids to names; everything else is
      # cast to string. Multi-valued fields are joined with ", ".
      # @param cfv [CustomFieldValue]
      # @return [String]
      def formatted(cfv)
        ids = Array(cfv.value).reject(&:blank?)
        return '' if ids.empty?

        case cfv.custom_field.field_format
        when 'user'
          Principal.where(id: ids).sort.map(&:name).join(', ')
        when 'version'
          Version.where(id: ids).order(:name).pluck(:name).join(', ')
        else
          ids.join(', ')
        end
      end
    end
  end
end
