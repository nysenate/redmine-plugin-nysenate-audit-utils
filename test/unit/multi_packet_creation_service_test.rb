require File.expand_path('../../test_helper', __FILE__)

class MultiPacketCreationServiceTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :attachments, :enabled_modules, :roles, :members, :member_roles

  def setup
    @issue1 = Issue.find(1)
    @issue2 = Issue.find(2)
    @issue3 = Issue.find(3)
    @issues = [@issue1, @issue2, @issue3]
    User.current = User.find(1)
  end

  def test_create_multi_packet_with_pdfs
    pdf_contents = {
      @issue1.id => "PDF content for issue 1",
      @issue2.id => "PDF content for issue 2", 
      @issue3.id => "PDF content for issue 3"
    }
    
    result = PacketCreationService.create_multi_packet(@issues, pdf_contents)
    
    assert_not_nil result
    assert result.is_a?(String)
    assert result.length > 0
    
    # Verify ZIP structure
    require 'zip'
    zip_buffer = StringIO.new(result)
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      # Check that packet directories exist
      assert zip_file.find_entry("packet_#{@issue1.id}/ticket_#{@issue1.id}.pdf")
      assert zip_file.find_entry("packet_#{@issue2.id}/ticket_#{@issue2.id}.pdf")
      assert zip_file.find_entry("packet_#{@issue3.id}/ticket_#{@issue3.id}.pdf")
      
      # Verify PDF contents
      pdf_entry1 = zip_file.find_entry("packet_#{@issue1.id}/ticket_#{@issue1.id}.pdf")
      assert_equal "PDF content for issue 1", pdf_entry1.get_input_stream.read
    end
  end

  def test_create_multi_packet_with_missing_pdf_content
    pdf_contents = {
      @issue1.id => "PDF content for issue 1",
      @issue2.id => "PDF content for issue 2"
      # Missing @issue3.id
    }
    
    assert_raises(RuntimeError, "Missing PDF content for issue #{@issue3.id}") do
      PacketCreationService.create_multi_packet(@issues, pdf_contents)
    end
  end

  def test_create_multi_packet_with_empty_issues
    assert_raises(ArgumentError, "No issues provided") do
      PacketCreationService.create_multi_packet([], {})
    end
  end

  def test_create_multi_packet_service_no_longer_checks_permissions
    # The service no longer checks permissions - that's handled by the controller now
    # This test just ensures the service can be called without permission errors
    # when the controller has already authorized the action
    
    # Create a user with no project memberships
    user_without_access = User.create!(
      login: "noaccess",
      firstname: "No",
      lastname: "Access",
      mail: "noaccess@example.com",
      status: User::STATUS_ACTIVE,
      admin: false
    )
    
    # Ensure the project is not public
    @issue1.project.update!(is_public: false)
    
    # Switch to a user without view permissions
    User.current = user_without_access
    
    # Service should work since it no longer checks permissions
    # (permissions are checked by the controller)
    result = PacketCreationService.create_multi_packet([@issue1], {@issue1.id => "PDF content"})
    
    assert_not_nil result
    assert result.is_a?(String)
    assert result.length > 0
  end


  def test_ensure_unique_filename
    # Test no conflict
    result = PacketCreationService.send(:ensure_unique_filename, "test.pdf", [])
    assert_equal "test.pdf", result
    
    # Test conflict resolution
    result = PacketCreationService.send(:ensure_unique_filename, "test.pdf", ["test.pdf"])
    assert_equal "test(1).pdf", result
    
    # Test multiple conflicts
    result = PacketCreationService.send(:ensure_unique_filename, "test.pdf", ["test.pdf", "test(1).pdf"])
    assert_equal "test(2).pdf", result
  end
end