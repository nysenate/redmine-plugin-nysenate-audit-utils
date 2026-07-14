# frozen_string_literal: true

# Base class for Audit Utils browser end-to-end (system) tests.
#
# Strategy: reuse Redmine core's ApplicationSystemTestCase (login helpers,
# download helpers, Setting cleanup) but swap the Selenium driver for
# Playwright, and stub the outbound ESS API at the Net::HTTP layer with
# WebMock.
#
# Why WebMock works here: Rails' SystemTestCase boots the Puma app server in
# a background *thread of this same process*. The browser is a separate
# process, but the app's call to the ESS API is an in-process Net::HTTP
# request -- so WebMock (which patches Net::HTTP globally) intercepts it,
# exactly as it does in the plugin's functional tests. The one requirement
# is `allow_localhost: true`, so WebMock does not sever the browser<->app
# and Capybara<->server localhost connections.

# Pulls in core test_helper, webmock/minitest, and AuditTestHelpers.
require File.expand_path('../test_helper', __FILE__)
# Core's Capybara/system-test base (defines ApplicationSystemTestCase).
require File.expand_path('../../../../test/application_system_test_case', __FILE__)

require 'capybara/playwright'

Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: (ENV['PLAYWRIGHT_BROWSER'] || 'chromium').to_sym,
    headless: ENV['PLAYWRIGHT_HEADFUL'].blank?
  )
end

class AuditUtilsSystemTestCase < ApplicationSystemTestCase
  # Override the Selenium driver inherited from ApplicationSystemTestCase.
  driven_by :playwright

  # Where the plugin's JSON fixtures live (reused from functional tests).
  FIXTURES_PATH = File.expand_path('../fixtures', __FILE__)

  ESS_BASE_URL = 'https://ess.test.local/'
  ESS_API_KEY  = 'test-api-key'

  setup do
    # NOTE: core's ApplicationSystemTestCase#setup has already run here and
    # cleared all Settings, so configure the plugin AFTER calling super's setup
    # (Minitest runs parent setup callbacks before child ones).
    WebMock.enable!
    # Let browser<->app and Capybara<->server localhost traffic through;
    # block everything else so an un-stubbed ESS call fails loudly.
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    # Re-open the network for any non-system tests sharing this process.
    WebMock.allow_net_connect!
  end

  private

  # Point EssConfiguration at our fake host so EssApiClient#validate_configuration!
  # passes. `configure_audit_fields`/`setup_standard_bachelp_fields` REPLACE the
  # whole plugin settings hash, so merge ESS keys in afterwards.
  def configure_ess!
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'ess_base_url' => ESS_BASE_URL,
      'ess_api_key'  => ESS_API_KEY
    )
  end

  # Stub the ESS employee-search endpoint with a canned fixture body.
  # The app builds the URL via URI.join(base_url, '/api/v1/redmine/employee/search').
  def stub_ess_employee_search(fixture: 'employee_search_response.json')
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/employee/search})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: File.read(File.join(FIXTURES_PATH, fixture))
      )
  end
end
