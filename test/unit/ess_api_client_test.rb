# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require 'webmock/minitest'

class EssApiClientTest < ActiveSupport::TestCase
  def setup
    WebMock.enable!
    @client = NysenateAuditUtils::Ess::EssApiClient.new('https://api.test.com', 'test-key-123')
    @employee_search_fixture = load_fixture('employee_search_response.json')
    @status_changes_fixture = load_fixture('status_changes_response.json')
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  def test_get_successful_request
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .with(headers: {
              'X-API-Key' => 'test-key-123',
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
            })
      .to_return(status: 200, body: @employee_search_fixture, headers: {})

    result = @client.get('/redmine/employee/search')

    assert_not_nil result
    assert_equal true, result['success']
    assert_equal 'bachelp employee list', result['responseType']
    assert_equal 14379, result['total']
  end

  def test_get_with_params
    stub_request(:get, "https://api.test.com/redmine/employee/search?term=smith&limit=10")
      .with(headers: { 'X-API-Key' => 'test-key-123' })
      .to_return(status: 200, body: @employee_search_fixture, headers: {})

    result = @client.get('/redmine/employee/search', { term: 'smith', limit: 10 })

    assert_not_nil result
    assert_equal 14379, result['total']
  end

  def test_authentication_error
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_return(status: 401, body: '{"error": "Invalid API key"}', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::AuthenticationError do
      @client.get('/redmine/employee/search')
    end
  end

  def test_not_found_returns_nil
    stub_request(:get, "https://api.test.com/redmine/employee/999999")
      .to_return(status: 404, body: '{"error": "Employee not found"}', headers: {})

    result = @client.get('/redmine/employee/999999')
    assert_nil result
  end

  def test_server_error
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_return(status: 500, body: '{"error": "Internal server error"}', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::ApiError do
      @client.get('/redmine/employee/search')
    end
  end

  def test_network_timeout
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_timeout

    assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/redmine/employee/search')
    end
  end

  def test_connection_refused
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_raise(Errno::ECONNREFUSED)

    assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/redmine/employee/search')
    end
  end

  def test_invalid_json_response
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_return(status: 200, body: 'invalid json{', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::ApiError do
      @client.get('/redmine/employee/search')
    end
  end

  # A 404 whose body is not JSON means nothing answered as the ESS API -- ESS is
  # not deployed at the Base URL, or the URL is wrong. It must not be reported
  # as "record not found", which is how an outage used to be silently swallowed.
  def test_non_json_not_found_raises_unexpected_response
    stub_request(:get, "https://api.test.com/redmine/employee/999999")
      .to_return(status: 404,
                 body: '<!doctype html><html><title>HTTP Status 404</title></html>',
                 headers: { 'Content-Type' => 'text/html' })

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::UnexpectedResponseError do
      @client.get('/redmine/employee/999999')
    end
    assert_includes error.message, 'https://api.test.com'
    assert_includes error.message, 'ESS may not be deployed there'
  end

  def test_empty_body_not_found_raises_unexpected_response
    stub_request(:get, "https://api.test.com/redmine/employee/999999")
      .to_return(status: 404, body: '', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::UnexpectedResponseError do
      @client.get('/redmine/employee/999999')
    end
  end

  def test_non_json_success_body_raises_unexpected_response
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_return(status: 200, body: '<html>login page</html>',
                 headers: { 'Content-Type' => 'text/html' })

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::UnexpectedResponseError do
      @client.get('/redmine/employee/search')
    end
    assert_includes error.message, 'does not look like the ESS API'
  end

  def test_connection_refused_names_ess_and_base_url
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_raise(Errno::ECONNREFUSED)

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/redmine/employee/search')
    end
    assert_includes error.message, 'https://api.test.com'
    assert_includes error.message, 'does not appear to be running'
  end

  def test_unknown_host_names_ess_and_base_url
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_raise(SocketError.new('getaddrinfo: Name or service not known'))

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/redmine/employee/search')
    end
    assert_includes error.message, 'Cannot reach ESS at https://api.test.com'
  end

  def test_timeout_names_ess_and_base_url
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_raise(Net::ReadTimeout)

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/redmine/employee/search')
    end
    assert_includes error.message, 'ESS did not respond'
  end

  def test_server_error_message_names_ess
    stub_request(:get, "https://api.test.com/redmine/employee/search")
      .to_return(status: 503, body: 'upstream down', headers: {})

    error = assert_raises NysenateAuditUtils::Ess::EssApiClient::ApiError do
      @client.get('/redmine/employee/search')
    end
    assert_includes error.message, 'ESS returned a server error (HTTP 503)'
  end

  private

  def load_fixture(filename)
    File.read(File.join(Rails.root, 'plugins', 'nysenate_audit_utils', 'test', 'fixtures', filename))
  end
end
