# frozen_string_literal: true

# Load the Redmine helper
require File.expand_path('../../../../test/test_helper', __FILE__)

# Load webmock for API testing
require 'webmock/minitest'

# Load Audit Utils-specific test helpers
require File.expand_path('../audit_test_helpers', __FILE__)

# Load plugin test support
class NysenateAuditUtilsTestCase < ActiveSupport::TestCase
  # Add common test helper methods here

  def setup
    # Set up proper attachment storage path for tests
    set_tmp_attachments_directory

    # Clear any existing attachments directory
    FileUtils.rm_rf(Dir.glob("#{Rails.root}/tmp/test/attachments/*"))

    # Ensure test directories exist
    FileUtils.mkdir_p "#{Rails.root}/tmp/test/attachments"
  end

  def teardown
    # Clean up after tests
    FileUtils.rm_rf(Dir.glob("#{Rails.root}/tmp/test/attachments/*"))
  end

  def mock_ess_api_response(status: 200, body: {})
    stub_request(:get, /.*/)
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def create_test_attachment(container, filename = "test.txt", content = nil)
    # Use Rails' fixture_file_upload helper like Redmine core tests do
    # Always use 'testfile.txt' fixture but rename to desired filename
    uploaded_file = uploaded_test_file('testfile.txt', 'text/plain')

    Attachment.create!(
      container: container,
      file: uploaded_file,
      filename: filename,
      author: User.find(1)
    )
  end

  def enable_packet_creation_module(project)
    project.enabled_module_names += ['audit_utils']
    project.save!
  end

  def grant_packet_creation_permission(role)
    role.add_permission! :create_packet
  end
end

# Include Audit Utils test helpers in all tests
class ActiveSupport::TestCase
  include AuditTestHelpers
end
