require File.expand_path('../../test_helper', __FILE__)

class PacketCreationControllerMultiTest < Redmine::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses, :trackers,
           :projects_trackers, :enabled_modules, :enumerations, :attachments, :custom_fields,
           :custom_values, :journals, :journal_details

  def setup
    set_tmp_attachments_directory
    @request.session[:user_id] = 1 # admin user
    @project = Project.find(1)
    @controller = PacketCreationController.new
    
    # Ensure user has view_issues permission
    role = Role.find(1)
    role.add_permission! :view_issues
  end

  def test_create_multi_packet_success
    issue_ids = [1, 2, 3]
    
    post :create_multi_packet, params: { ids: issue_ids }
    
    assert_response :success
    assert_equal 'application/zip', @response.content_type
    assert_match /multi_packet_\d{8}_\d{6}\.zip/, @response.headers['Content-Disposition']
    
    # Verify ZIP structure
    require 'zip'
    zip_buffer = StringIO.new(@response.body)
    Zip::File.open_buffer(zip_buffer) do |zip_file|
      issue_ids.each do |issue_id|
        assert zip_file.find_entry("packet_#{issue_id}/ticket_#{issue_id}.pdf"), 
               "Missing packet_#{issue_id}/ticket_#{issue_id}.pdf"
      end
    end
  end

  def test_create_multi_packet_no_issues
    post :create_multi_packet, params: { ids: [] }
    
    assert_response :redirect
    assert_match /No issues selected/, flash[:error]
  end

  def test_create_multi_packet_missing_ids
    post :create_multi_packet, params: {}
    
    assert_response :redirect
    assert_match /No issues selected/, flash[:error]
  end

  def test_create_multi_packet_nonexistent_issue
    post :create_multi_packet, params: { ids: [999999] }
    
    assert_response :not_found
  end

  def test_create_multi_packet_permission_denied
    # Create a user with no project memberships
    user_no_permission = User.create!(
      login: "noaccess",
      firstname: "No",
      lastname: "Access",
      mail: "noaccess@example.com",
      status: User::STATUS_ACTIVE,
      admin: false
    )
    
    # Ensure the project is not public
    @project.update!(is_public: false)
    
    @request.session[:user_id] = user_no_permission.id
    
    post :create_multi_packet, params: { ids: [1, 2, 3] }
    
    assert_response :not_found
  end
end