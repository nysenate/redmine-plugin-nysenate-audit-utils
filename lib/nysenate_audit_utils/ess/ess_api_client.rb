require 'net/http'
require 'json'
require 'uri'

module NysenateAuditUtils
  module Ess
    class EssApiClient
      class ApiError < StandardError; end

      class AuthenticationError < ApiError; end

      class NetworkError < ApiError; end

      def initialize(base_url = nil, api_key = nil)
        @base_url = base_url || NysenateAuditUtils::Ess::EssConfiguration.base_url
        @api_key = api_key || NysenateAuditUtils::Ess::EssConfiguration.api_key
        @timeout = 30
      end

      def get(path, params = {})
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        add_headers(request)

        make_request(uri, request)
      rescue StandardError => e
        handle_error(e)
      end

      private

      def build_uri(path, params)
        uri = URI.join(@base_url, path)
        unless params.empty?
          uri.query = URI.encode_www_form(params)
        end
        uri
      end

      def add_headers(request)
        request['X-API-Key'] = @api_key
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
      end

      def make_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        response = http.request(request)
        handle_response(response)
      end

      def handle_response(response)
        case response.code.to_i
        when 200
          JSON.parse(response.body)
        when 401
          Rails.logger.error "ESS API authentication failed"
          raise AuthenticationError, "API authentication failed"
        when 404
          Rails.logger.warn "ESS API resource not found: #{response.body}"
          nil
        when 400..499
          Rails.logger.error "ESS API client error (#{response.code}): #{response.body}"
          raise ApiError, "Client error: #{response.code}"
        when 500..599
          Rails.logger.error "ESS API server error (#{response.code}): #{response.body}"
          raise ApiError, "Server error: #{response.code}"
        else
          Rails.logger.error "ESS API unexpected response (#{response.code}): #{response.body}"
          raise ApiError, "Unexpected response: #{response.code}"
        end
      rescue JSON::ParserError => e
        Rails.logger.error "ESS API invalid JSON response: #{e.message}"
        raise ApiError, "Invalid JSON response"
      end

      def handle_error(error)
        case error
        when Net::OpenTimeout, Net::ReadTimeout
          Rails.logger.error "ESS API timeout: #{error.message}"
          raise NetworkError, "Request timeout"
        when SocketError, Errno::ECONNREFUSED
          Rails.logger.error "ESS API connection error: #{error.message}"
          raise NetworkError, "Connection failed"
        when ApiError
          raise error
        else
          Rails.logger.error "ESS API unexpected error: #{error.message}"
          raise ApiError, "Unexpected error: #{error.message}"
        end
      end
    end
  end
end