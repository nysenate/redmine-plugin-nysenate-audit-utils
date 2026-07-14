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
#
# ---------------------------------------------------------------------------
# TEST DATA POLICY: never use real employee/vendor/volunteer data. All names,
# emails, phone numbers, and IDs seeded by these helpers (and by the JSON
# fixtures they read) must be obviously synthetic (e.g. "Ada Testwell",
# employeeId 900001). Do not paste production ESS payloads into fixtures.
# ---------------------------------------------------------------------------

# Pulls in core test_helper, webmock/minitest, and AuditTestHelpers.
require File.expand_path('../test_helper', __FILE__)
# Core's Capybara/system-test base (defines ApplicationSystemTestCase).
require File.expand_path('../../../../test/application_system_test_case', __FILE__)

require 'capybara/playwright'
require 'csv'
require 'zip'

Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: (ENV['PLAYWRIGHT_BROWSER'] || 'chromium').to_sym,
    headless: ENV['PLAYWRIGHT_HEADFUL'].blank?
  )
end

# The Playwright driver saves every download to `Capybara.save_path` using the
# response's suggested filename (see capybara-playwright-driver's page.rb
# `on('download', ...)`). Core's Selenium base instead points Chrome at
# `DOWNLOADS_PATH`, so we must set `save_path` ourselves -- it defaults to nil,
# which would make the driver's File.join blow up on the first download. Set it
# at load time (before any setup callback runs) and keep it separate from
# core's Chrome dir so the two suites never see each other's files.
Capybara.save_path = File.expand_path('tmp/audit_downloads', Rails.root)

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

  # ==========================================================================
  # One-call project setup
  # ==========================================================================

  # Prepare a project for Audit Utils e2e testing: map the standard Account
  # Holder / request custom fields onto its tracker, point ESS at the fake host,
  # and enable the `audit_utils` module. Most tests only need this plus a login.
  #
  # @param project [Project] defaults to fixture project 1
  # @param tracker [Tracker] defaults to fixture tracker 1
  # @param fields [Boolean] map the standard custom fields (default true)
  # @param ess [Boolean]    configure ESS host/key (default true)
  # @param enable_module [Boolean] enable the audit_utils module (default true)
  # @return [Array(Project, Tracker, Hash)] project, tracker, and (if built) the
  #   field map returned by setup_standard_bachelp_fields (nil when fields:false)
  def setup_audit_utils_project(project: Project.find(1), tracker: Tracker.find(1),
                                fields: true, ess: true, enable_module: true)
    field_map = fields ? setup_standard_bachelp_fields(tracker) : nil
    # configure_ess! must run AFTER field setup -- setup_standard_bachelp_fields
    # REPLACES the whole plugin settings hash.
    configure_ess! if ess
    project.enable_module!(:audit_utils) if enable_module
    [project, tracker, field_map]
  end

  # Point EssConfiguration at our fake host so EssApiClient#validate_configuration!
  # passes. `configure_audit_fields`/`setup_standard_bachelp_fields` REPLACE the
  # whole plugin settings hash, so merge ESS keys in afterwards.
  def configure_ess!
    Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
      'ess_base_url' => ESS_BASE_URL,
      'ess_api_key'  => ESS_API_KEY
    )
  end

  # ==========================================================================
  # Login / permissions
  # ==========================================================================

  # Log in as the fixture admin (passes every allowed_to? check).
  def log_in_as_admin
    log_user('admin', 'admin')
  end

  # Create a non-admin user who is a member of `project` via a fresh role
  # carrying exactly `permissions`, then return the user (NOT logged in). Use
  # this to prove features are gated -- grant a subset and assert the rest is
  # denied/absent. All identity data is synthetic.
  #
  # @param permissions [Array<Symbol>] e.g. [:view_audit_reports]
  # @param login [String] unique login for the seeded user
  # @param project [Project]
  # @return [User]
  def create_member_with_permissions(permissions, login: "audit_e2e_#{SecureRandom.hex(4)}", project: Project.find(1))
    user = User.generate!(login: login, password: 'audit_e2e_pass', firstname: 'Audit', lastname: 'Tester')
    user.update!(must_change_passwd: false)
    role = Role.generate!(name: "Audit E2E #{SecureRandom.hex(4)}", permissions: permissions)
    Member.create!(principal: user, project: project, roles: [role])
    user
  end

  # Convenience: seed a non-admin member with `permissions` and log in as them.
  # Returns the user. `project` must have the audit_utils module enabled for the
  # project-scoped permissions to take effect.
  def log_in_with_permissions(permissions, project: Project.find(1))
    user = create_member_with_permissions(permissions, project: project)
    log_user(user.login, 'audit_e2e_pass')
    user
  end

  # ==========================================================================
  # ESS stubs (WebMock, in-process)
  # ==========================================================================

  # Stub the ESS employee-search endpoint with a canned fixture body.
  # The app builds the URL via URI.join(base_url, '/api/v1/redmine/employee/search').
  # Also covers the config page's "Test ESS Connection" button, which hits the
  # same endpoint.
  def stub_ess_employee_search(fixture: 'employee_search_response.json')
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/employee/search})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: File.read(File.join(FIXTURES_PATH, fixture))
      )
  end
  alias stub_ess_connection_success stub_ess_employee_search

  # Stub the ESS employee-search endpoint to fail, for the config page's
  # "Test ESS Connection" error path.
  def stub_ess_connection_failure(status: 500)
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/employee/search})
      .to_return(status: status, body: 'ESS unavailable')
  end

  # Stub the ESS status-changes endpoint used by the Daily Report.
  def stub_ess_status_changes(fixture: 'status_changes_response.json')
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/statusChanges})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: File.read(File.join(FIXTURES_PATH, fixture))
      )
  end

  # Stub a single-employee lookup (/api/v1/redmine/employee/:id).
  #
  # NOTE the response SHAPE differs from search: EssEmployeeService.find_by_id
  # reads `response['employee']` (a single object), whereas search reads
  # `response['result']` (an array). Passing the search fixture body here would
  # make find_by_id return nil. So we wrap a single employee object under the
  # `employee` key. By default we reuse the first synthetic employee from the
  # search fixture (keeping all test data in one place); pass `employee:` to
  # override with a specific synthetic hash.
  def stub_ess_employee_lookup(employee_id, employee: nil)
    employee ||= JSON.parse(File.read(File.join(FIXTURES_PATH, 'employee_search_response.json')))
                     .fetch('result').first
    body = { 'success' => true, 'message' => '', 'employee' => employee }
    stub_request(:get, %r{\A#{Regexp.escape(ESS_BASE_URL)}api/v1/redmine/employee/#{employee_id}\b})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: body.to_json
      )
  end

  # ==========================================================================
  # Downloads (CSV / ZIP) -- Playwright saves to Capybara.save_path
  # ==========================================================================

  # Override core's Chrome-oriented helper: the Playwright driver writes to
  # Capybara.save_path, not DOWNLOADS_PATH. Newest-last, ignoring in-progress
  # temp files.
  def downloaded_files(filename = '*')
    Dir.glob(File.join(Capybara.save_path.to_s, filename))
       .reject { |f| f =~ /\.(tmp|crdownload|part)\z/ }
       .sort_by { |f| File.mtime(f) }
  end

  def clear_downloaded_files
    FileUtils.rm_f(downloaded_files)
  end

  # Trigger a download (via the passed block, e.g. clicking an Export link) and
  # return the path of the resulting file. The driver saves downloads on a
  # background thread, so poll until it lands. Clears prior downloads first so
  # the returned file is unambiguously the one this block produced.
  #
  #   path = capture_download { click_link 'Export to CSV' }
  #
  # @param filename [String] glob to match (default any)
  # @param timeout [Integer] seconds to wait
  # @return [String] path to the downloaded file
  def capture_download(filename = '*', timeout: 15)
    clear_downloaded_files
    yield
    wait_for_download(filename, timeout: timeout)
  end

  # Wait for a download matching `filename` to appear and return its path.
  def wait_for_download(filename = '*', timeout: 15)
    Timeout.timeout(timeout) do
      loop do
        file = downloaded_files(filename).last
        # Guard against reading a file mid-write.
        return file if file && File.size?(file)

        sleep 0.2
      end
    end
  rescue Timeout::Error
    flunk "No download matching #{filename.inspect} appeared in #{Capybara.save_path} within #{timeout}s " \
          "(saw: #{Dir.glob(File.join(Capybara.save_path.to_s, '*')).map { |f| File.basename(f) }.inspect})"
  end

  # Parse a downloaded CSV. Returns a CSV::Table (headers: true) by default.
  #
  #   table = downloaded_csv { click_link 'Export to CSV' }
  #   assert_includes table.headers, 'Account Holder Name'
  #
  # @param headers [Boolean] parse the first row as headers (default true)
  def downloaded_csv(filename = '*.csv', headers: true, &block)
    path = block ? capture_download(filename, &block) : wait_for_download(filename)
    CSV.read(path, headers: headers, encoding: 'bom|utf-8')
  end

  # Return the entry names inside a downloaded ZIP, for asserting a packet's
  # contents (e.g. the ticket PDF + attachments) without unpacking to disk.
  #
  #   names = downloaded_zip_entries { click_button 'Create Packet' }
  #   assert names.any? { |n| n.end_with?('.pdf') }
  def downloaded_zip_entries(filename = '*.zip', &block)
    path = block ? capture_download(filename, &block) : wait_for_download(filename)
    Zip::File.open(path) { |zip| zip.map(&:name) }
  end
end
