# frozen_string_literal: true

require_relative '../test_helper'

class PacketCreationServiceTest < NysenateAuditUtilsTestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :attachments

  def setup
    super
    @issue = Issue.find(1)
  end

  def test_create_packet_with_no_attachments
    # Remove any existing attachments
    @issue.attachments.destroy_all
    
    # Mock PDF content
    pdf_content = "%PDF-1.4\nfake pdf content"
    
    packet_zip = PacketCreationService.create_packet(@issue, pdf_content)
    
    assert_not_nil packet_zip
    assert packet_zip.length > 0
    
    # Parse the zip to verify contents
    zip_buffer = StringIO.new(packet_zip)
    filenames = []
    
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      zip_file.each do |entry|
        filenames << entry.name
      end
    end
    
    assert_equal 1, filenames.length
    assert_includes filenames, "ticket_1.pdf"
  end

  def test_create_packet_with_attachments
    
    # Create test attachments
    attachment1 = create_test_attachment(@issue, "test1.txt")
    attachment2 = create_test_attachment(@issue, "test2.txt")
    
    # Mock PDF content
    pdf_content = "%PDF-1.4\nfake pdf content"
    
    packet_zip = PacketCreationService.create_packet(@issue, pdf_content)
    
    assert_not_nil packet_zip
    assert packet_zip.length > 0
    
    # Parse the zip to verify contents
    zip_buffer = StringIO.new(packet_zip)
    filenames = []
    file_contents = {}
    
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      zip_file.each do |entry|
        filenames << entry.name
        file_contents[entry.name] = entry.get_input_stream.read
      end
    end
    
    assert_equal 3, filenames.length
    assert_includes filenames, "ticket_1.pdf"
    assert_includes filenames, "test1.txt"
    assert_includes filenames, "test2.txt"
    
    # Verify file contents (both files use same fixture content)
    expected_content = "this is a text file for upload tests\r\nwith multiple lines\r\n"
    assert_equal expected_content, file_contents["test1.txt"]
    assert_equal expected_content, file_contents["test2.txt"]
    
    # Verify PDF is present and has content
    assert file_contents["ticket_1.pdf"].length > 0
    assert file_contents["ticket_1.pdf"].start_with?("%PDF")
  end

  def test_create_packet_with_duplicate_filenames
    
    # Create attachments with duplicate names
    attachment1 = create_test_attachment(@issue, "duplicate.txt")
    attachment2 = create_test_attachment(@issue, "duplicate.txt")
    attachment3 = create_test_attachment(@issue, "duplicate.txt")
    
    # Mock PDF content
    pdf_content = "%PDF-1.4\nfake pdf content"
    
    packet_zip = PacketCreationService.create_packet(@issue, pdf_content)
    
    # Parse the zip to verify contents
    zip_buffer = StringIO.new(packet_zip)
    filenames = []
    file_contents = {}
    
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      zip_file.each do |entry|
        filenames << entry.name
        file_contents[entry.name] = entry.get_input_stream.read
      end
    end
    
    assert_equal 4, filenames.length
    assert_includes filenames, "ticket_1.pdf"
    assert_includes filenames, "duplicate.txt"
    assert_includes filenames, "duplicate(1).txt"
    assert_includes filenames, "duplicate(2).txt"
    
    # Verify each file has the correct content (all use same fixture content)
    expected_content = "this is a text file for upload tests\r\nwith multiple lines\r\n"
    assert_equal expected_content, file_contents["duplicate.txt"]
    assert_equal expected_content, file_contents["duplicate(1).txt"]
    assert_equal expected_content, file_contents["duplicate(2).txt"]
  end

  def test_ensure_unique_filename
    # Test with no duplicates
    result = PacketCreationService.send(:ensure_unique_filename, "test.txt", [])
    assert_equal "test.txt", result
    
    # Test with one duplicate
    result = PacketCreationService.send(:ensure_unique_filename, "test.txt", ["test.txt"])
    assert_equal "test(1).txt", result
    
    # Test with multiple duplicates
    result = PacketCreationService.send(:ensure_unique_filename, "test.txt", ["test.txt", "test(1).txt", "test(2).txt"])
    assert_equal "test(3).txt", result
    
    # Test with files without extensions
    result = PacketCreationService.send(:ensure_unique_filename, "README", ["README"])
    assert_equal "README(1)", result
    
    # Test with complex extensions
    result = PacketCreationService.send(:ensure_unique_filename, "test.tar.gz", ["test.tar.gz"])
    assert_equal "test.tar(1).gz", result
  end

  def test_create_packet_with_unreadable_attachment
    
    # Create a regular attachment first
    attachment1 = create_test_attachment(@issue, "readable.txt")
    
    # Create an attachment that references a non-existent file
    attachment2 = Attachment.new(
      container: @issue,
      filename: "unreadable.txt",
      author: User.find(1),
      filesize: 100,
      content_type: "text/plain"
    )
    attachment2.save!(validate: false)
    
    # Mock PDF content
    pdf_content = "%PDF-1.4\nfake pdf content"
    
    packet_zip = PacketCreationService.create_packet(@issue, pdf_content)
    
    # Parse the zip to verify contents
    zip_buffer = StringIO.new(packet_zip)
    filenames = []
    
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      zip_file.each do |entry|
        filenames << entry.name
      end
    end
    
    # Should include PDF and readable attachment, but not unreadable one
    assert_equal 2, filenames.length
    assert_includes filenames, "ticket_1.pdf"
    assert_includes filenames, "readable.txt"
    assert_not_includes filenames, "unreadable.txt"
  end

  def test_create_packet_with_pdf_handles_zip_errors
    # Mock the zip creation to raise an error
    PacketCreationService.expects(:create_zip_with_attachments).raises(StandardError.new("Zip creation failed"))
    
    assert_raises(StandardError) do
      PacketCreationService.create_packet(@issue, "fake pdf content")
    end
  end
end