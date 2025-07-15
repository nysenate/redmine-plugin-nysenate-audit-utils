# frozen_string_literal: true

# Load the Redmine test helper
require File.expand_path('../../../test/test_helper', __dir__)

# Plugin-specific test setup
class PacketCreationTestCase < ActiveSupport::TestCase
  def setup
    # Clear any existing attachments directory
    FileUtils.rm_rf(Dir.glob("#{Rails.root}/tmp/test/attachments/*"))
    
    # Ensure test directories exist
    FileUtils.mkdir_p "#{Rails.root}/tmp/test/attachments"
  end

  def teardown
    # Clean up after tests
    FileUtils.rm_rf(Dir.glob("#{Rails.root}/tmp/test/attachments/*"))
  end

  protected

  def create_test_attachment(container, filename = "test.txt", content = "test content")
    file = Rails.root.join('tmp/test/attachments', filename)
    File.write(file, content)
    
    Attachment.create!(
      container: container,
      file: ActionDispatch::Http::UploadedFile.new(
        tempfile: file,
        filename: filename,
        type: 'text/plain'
      ),
      filename: filename,
      author: User.find(1)
    )
  end

  def enable_packet_creation_module(project)
    project.enabled_module_names += ['bachelp_packet_creation']
    project.save!
  end

  def grant_packet_creation_permission(role)
    role.add_permission! :create_packet
  end
end