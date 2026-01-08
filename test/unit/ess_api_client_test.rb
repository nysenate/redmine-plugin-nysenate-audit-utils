require File.expand_path('../../test_helper', __FILE__)
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
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .with(headers: {
        'X-API-Key' => 'test-key-123',
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      })
      .to_return(status: 200, body: @employee_search_fixture, headers: {})

    result = @client.get('/bachelp/employee/search')

    assert_not_nil result
    assert_equal true, result['success']
    assert_equal 'bachelp employee list', result['responseType']
    assert_equal 14379, result['total']
  end

  def test_get_with_params
    stub_request(:get, "https://api.test.com/bachelp/employee/search?term=smith&limit=10")
      .with(headers: { 'X-API-Key' => 'test-key-123' })
      .to_return(status: 200, body: @employee_search_fixture, headers: {})

    result = @client.get('/bachelp/employee/search', { term: 'smith', limit: 10 })

    assert_not_nil result
    assert_equal 14379, result['total']
  end

  def test_authentication_error
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .to_return(status: 401, body: '{"error": "Invalid API key"}', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::AuthenticationError do
      @client.get('/bachelp/employee/search')
    end
  end

  def test_not_found_returns_nil
    stub_request(:get, "https://api.test.com/bachelp/employee/999999")
      .to_return(status: 404, body: '{"error": "Employee not found"}', headers: {})

    result = @client.get('/bachelp/employee/999999')
    assert_nil result
  end

  def test_server_error
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .to_return(status: 500, body: '{"error": "Internal server error"}', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::ApiError do
      @client.get('/bachelp/employee/search')
    end
  end

  def test_network_timeout
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .to_timeout

    assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/bachelp/employee/search')
    end
  end

  def test_connection_refused
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .to_raise(Errno::ECONNREFUSED)

    assert_raises NysenateAuditUtils::Ess::EssApiClient::NetworkError do
      @client.get('/bachelp/employee/search')
    end
  end

  def test_invalid_json_response
    stub_request(:get, "https://api.test.com/bachelp/employee/search")
      .to_return(status: 200, body: 'invalid json{', headers: {})

    assert_raises NysenateAuditUtils::Ess::EssApiClient::ApiError do
      @client.get('/bachelp/employee/search')
    end
  end

  private

  def load_fixture(filename)
    File.read(File.join(Rails.root, 'plugins', 'nysenate_audit_utils', 'test', 'fixtures', filename))
  end
end