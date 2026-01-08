module NysenateAuditUtils
  module Ess
    class EssConfiguration
      def self.base_url
        Setting.plugin_nysenate_audit_utils['ess_base_url']
      end

      def self.api_key
        Setting.plugin_nysenate_audit_utils['ess_api_key']
      end

    def self.valid?
      base_url.present? && api_key.present? && valid_url?(base_url)
    end

    def self.validation_errors
      errors = []
      errors << "ESS Base URL is required" if base_url.blank?
      errors << "ESS API Key is required" if api_key.blank?
      errors << "ESS Base URL must be a valid URL" if base_url.present? && !valid_url?(base_url)
      errors
    end

    private

    def self.valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end
    end
  end
end