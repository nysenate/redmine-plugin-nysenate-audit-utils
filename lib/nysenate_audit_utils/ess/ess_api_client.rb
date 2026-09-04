# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module NysenateAuditUtils
  module Ess
    class EssApiClient
      class ApiError < StandardError; end

      class AuthenticationError < ApiError; end

      class NetworkError < ApiError; end

      # Raised when something answers at the configured Base URL but it does
      # not behave like the ESS API (non-JSON body, container/proxy error
      # page). Distinct from NetworkError so callers can tell "ESS is not
      # deployed here" from "nothing is listening".
      class UnexpectedResponseError < ApiError; end

      def initialize(base_url = nil, api_key = nil)
        @base_url = base_url || NysenateAuditUtils::Ess::EssConfiguration.base_url
        @api_key = api_key || NysenateAuditUtils::Ess::EssConfiguration.api_key
        @timeout = 30
        validate_configuration!
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

      def validate_configuration!
        if @base_url.blank?
          raise ApiError, "ESS Base URL is not configured. Please configure it in Administration → Plugins → NY Senate Audit Utils → Configure"
        end

        if @api_key.blank?
          raise ApiError, "ESS API Key is not configured. Please configure it in Administration → Plugins → NY Senate Audit Utils → Configure"
        end

        begin
          uri = URI.parse(@base_url)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            raise ApiError, "ESS Base URL must be a valid HTTP or HTTPS URL"
          end
        rescue URI::InvalidURIError
          raise ApiError, "ESS Base URL is not a valid URL: #{@base_url}"
        end
      end

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
        handle_response(response, uri)
      end

      def handle_response(response, uri)
        case response.code.to_i
        when 200
          parse_json!(response, uri)
        when 401
          Rails.logger.error "ESS API authentication failed (401) for #{uri}"
          raise AuthenticationError, 'ESS authentication failed'
        when 404
          handle_not_found(response, uri)
        when 400..499
          Rails.logger.error "ESS API client error (#{response.code}): #{response.body}"
          raise ApiError, "ESS returned HTTP #{response.code}"
        when 500..599
          Rails.logger.error "ESS API server error (#{response.code}): #{response.body}"
          raise ApiError, "ESS server error (HTTP #{response.code})"
        else
          Rails.logger.error "ESS API unexpected response (#{response.code}): #{response.body}"
          raise ApiError, "ESS returned an unexpected HTTP #{response.code}"
        end
      end

      # ESS answers a genuine "no such record" with a JSON error body (see the
      # NotFound response in the ESS OpenAPI spec), which is a normal outcome
      # callers handle as nil. A 404 carrying anything else -- a servlet
      # container or proxy error page -- means we never reached the ESS API at
      # all: ESS is not deployed at the Base URL, or the URL is wrong. That is
      # a connection problem and must not masquerade as "record not found".
      def handle_not_found(response, uri)
        if json_object(response)
          Rails.logger.warn "ESS API resource not found: #{response.body}"
          return nil
        end

        Rails.logger.error(
          "ESS API returned a non-JSON 404 for #{uri}: #{response.body.to_s.first(200)}"
        )
        raise UnexpectedResponseError, 'ESS connection error (unexpected response)'
      end

      def parse_json!(response, uri)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        Rails.logger.error "ESS API invalid JSON response from #{uri}: #{e.message}"
        raise UnexpectedResponseError, 'ESS connection error (unexpected response)'
      end

      # Parsed response body when it is a JSON object, else nil.
      def json_object(response)
        return nil if response.body.blank?

        parsed = JSON.parse(response.body)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      def handle_error(error)
        case error
        when Net::OpenTimeout, Net::ReadTimeout
          Rails.logger.error "ESS API timeout for #{@base_url}: #{error.message}"
          raise NetworkError, 'ESS connection error (timed out)'
        when Errno::ECONNREFUSED
          Rails.logger.error "ESS API connection refused by #{@base_url}: #{error.message}"
          raise NetworkError, 'ESS connection error (connection refused)'
        when SocketError
          Rails.logger.error "ESS API cannot reach #{@base_url}: #{error.message}"
          raise NetworkError, 'ESS connection error (host unreachable)'
        when Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ECONNRESET, Errno::EPIPE
          Rails.logger.error "ESS API network error for #{@base_url}: #{error.message}"
          raise NetworkError, 'ESS connection error'
        when ApiError
          raise error
        else
          Rails.logger.error "ESS API unexpected error for #{@base_url}: #{error.class}: #{error.message}"
          raise ApiError, 'ESS connection error'
        end
      end
    end
  end
end
