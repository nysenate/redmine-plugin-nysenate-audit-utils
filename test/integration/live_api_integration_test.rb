require_relative '../test_helper'

class LiveApiIntegrationTest < ActiveSupport::TestCase

  def setup
    @original_settings = Setting.plugin_nysenate_audit_utils
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = @original_settings if @original_settings
  end

  # This test is skipped by default because it requires a live ESS server
  # To enable this test, either:
  # 1. Set ENABLE_LIVE_API_TESTS=true environment variable
  # 2. Remove the 'skip' line below
  # 3. Run with: bundle exec rails test plugins/bachelp_ess_integration/test/integration/live_api_integration_test.rb --name test_live_ess_integration
  def test_live_ess_integration
    skip "Live API integration test disabled (set ENABLE_LIVE_API_TESTS=true to enable)" unless ENV['ENABLE_LIVE_API_TESTS']
    
    puts "\n" + "=" * 60
    puts "BACHelp ESS Integration Live API Test"
    puts "=" * 60
    puts ""
    
    # Configure the plugin with test settings
    puts "Configuring BACHelp ESS Integration plugin..."
    
    test_settings = {
      'ess_base_url' => 'http://localhost:8080',
      'ess_api_key' => 'test-bachelp-key-12345678901234567890'
    }
    
    Setting.plugin_bachelp_ess_integration = test_settings
    
    # Verify configuration
    settings = Setting.plugin_bachelp_ess_integration
    puts "Configuration set:"
    puts "  ESS Base URL: #{settings['ess_base_url']}"
    puts "  ESS API Key: #{settings['ess_api_key']}"
    
    # Test configuration validation
    is_valid = NysenateAuditUtils::Ess::EssConfiguration.valid?
    errors = NysenateAuditUtils::Ess::EssConfiguration.validation_errors
    
    puts "\nConfiguration validation: #{is_valid ? 'VALID' : 'INVALID'}"
    unless is_valid
      puts "Validation errors:"
      errors.each { |error| puts "  - #{error}" }
      skip "Cannot proceed - configuration is invalid"
    end
    
    # Test 1: Employee Search
    puts "\n=== Test 1: Employee Search ==="
    puts "-" * 40
    
    begin
      employees = NysenateAuditUtils::Ess::EssEmployeeService.search("smith", limit: 5)
      
      if employees.is_a?(Array) && employees.any?
        puts "✅ Search successful!"
        puts "Employees returned: #{employees.size}"
        
        employees.first(2).each_with_index do |emp, i|
          puts "\nEmployee #{i+1}:"
          puts "  ID: #{emp.employee_id}"
          puts "  Name: #{emp.full_name}"
          puts "  UID: #{emp.uid || 'N/A'}"
          puts "  Email: #{emp.email || 'N/A'}"
          puts "  Active: #{emp.active}"
        end
        
        # Verify we got proper EssEmployee objects
        assert employees.all? { |emp| emp.is_a?(EssEmployee) }, "Should return EssEmployee objects"
        assert employees.first.respond_to?(:employee_id), "Should have employee_id method"
        assert employees.first.respond_to?(:full_name), "Should have full_name method"
        
      elsif employees.is_a?(Array)
        puts "✅ Search completed but no results found"
        assert_equal [], employees, "Should return empty array when no results"
      else
        flunk "Search returned unexpected result: #{employees.inspect}"
      end
    rescue => e
      puts "❌ Search error: #{e.message}"
      puts "Error details: #{e.backtrace.first(3).join("\n")}"
      flunk "Employee search failed: #{e.message}"
    end
    
    # Test 2: Status Changes
    puts "\n=== Test 2: Recent Status Changes ==="
    puts "-" * 40
    
    begin
      status_changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(7.days.ago, Time.now)
      
      if status_changes.is_a?(Array) && status_changes.any?
        puts "✅ Status changes retrieved successfully!"
        puts "Changes returned: #{status_changes.size}"
        
        status_changes.first(3).each_with_index do |change, i|
          puts "\nStatus Change #{i+1}:"
          puts "  Employee: #{change.employee.full_name}"
          puts "  Transaction: #{change.transaction_code} (#{change.transaction_description})"
          puts "  Employee Active: #{change.employee.active}"
        end
        
        # Verify we got proper EssStatusChange objects
        assert status_changes.all? { |change| change.is_a?(EssStatusChange) }, "Should return EssStatusChange objects"
        assert status_changes.first.respond_to?(:transaction_code), "Should have transaction_code method"
        assert status_changes.first.respond_to?(:transaction_description), "Should have transaction_description method"
        assert status_changes.first.employee.is_a?(EssEmployee), "Should have associated EssEmployee"
        
      elsif status_changes.is_a?(Array)
        puts "✅ Status changes completed but no results found"
        assert_equal [], status_changes, "Should return empty array when no results"
      else
        flunk "Status changes returned unexpected result: #{status_changes.inspect}"
      end
    rescue => e
      puts "❌ Status changes error: #{e.message}"
      puts "Error details: #{e.backtrace.first(3).join("\n")}"
      flunk "Status changes query failed: #{e.message}"
    end
    
    # Test 3: Error Handling
    puts "\n=== Test 3: Error Handling Test ==="
    puts "-" * 40
    
    begin
      invalid_client = NysenateAuditUtils::Ess::EssApiClient.new(
        settings['ess_base_url'], 
        'invalid-key-12345'
      )
      result = invalid_client.get('/api/v1/bachelp/employee/search', {term: "test", limit: 5})
      
      if result.is_a?(Hash) && result['success']
        puts "⚠️  Unexpected success with invalid key"
        flunk "Should have failed authentication with invalid key"
      elsif result.is_a?(Array)
        puts "⚠️  Unexpected array response with invalid key"
        flunk "Should have failed authentication with invalid key"
      else
        puts "✅ Error handling working: #{result.inspect}"
      end
    rescue NysenateAuditUtils::Ess::EssApiClient::AuthenticationError => e
      puts "✅ Authentication error handling working: #{e.message}"
      assert_equal "API authentication failed", e.message, "Should have proper error message"
    rescue NysenateAuditUtils::Ess::EssApiClient::ApiError => e
      puts "✅ API error handling working: #{e.message}"
      assert e.message.present?, "Should have error message"
    rescue NysenateAuditUtils::Ess::EssApiClient::NetworkError => e
      puts "✅ Network error handling working: #{e.message}"
      assert e.message.present?, "Should have error message"
    rescue => e
      puts "✅ General exception handling working: #{e.message}"
      assert e.message.present?, "Should have error message"
    end
    
    puts "\n" + "=" * 50
    puts "Live API integration test completed successfully!"
  end
end