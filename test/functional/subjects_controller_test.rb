require File.expand_path('../../test_helper', __FILE__)

class SubjectsControllerTest < ActionController::TestCase
  fixtures :users, :projects, :members, :roles, :member_roles, :enabled_modules

  def setup
    @admin = User.find(1)
    @user = User.find(2)

    # Create test project with subject management module enabled
    @project = Project.find(1)
    @project.enabled_module_names = ['audit_utils_subject_management']

    # Give the regular user the manage_subjects permission
    role = Role.find(1)
    role.add_permission! :manage_subjects

    # Create test subjects
    @vendor1 = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Test Vendor 1',
      email: 'vendor1@example.com',
      status: 'Active'
    )

    @vendor2 = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V2',
      name: 'Test Vendor 2',
      email: 'vendor2@example.com',
      status: 'Inactive'
    )
  end

  # Index action tests

  def test_index_with_permission_shows_subjects
    @request.session[:user_id] = @user.id

    get :index, params: { project_id: @project.id }

    assert_response :success
    assert_select 'table.list.subjects'
    assert_select 'td', text: @vendor1.name
    assert_select 'td', text: @vendor2.name
  end

  def test_index_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  def test_index_without_login_redirects
    get :index, params: { project_id: @project.id }

    assert_response :redirect
    assert_redirected_to /\/login/
  end

  # New action tests

  def test_new_with_permission_shows_form
    @request.session[:user_id] = @user.id

    get :new, params: { project_id: @project.id }

    assert_response :success
    assert_select 'form'
    assert_select 'input[name=?]', 'subject[subject_id]'
  end

  def test_new_auto_generates_next_vendor_id
    @request.session[:user_id] = @user.id

    get :new, params: { project_id: @project.id }

    assert_response :success
    # Check that the form has the auto-generated vendor ID (V3 after V1 and V2)
    assert_select 'input[name=?][value=?]', 'subject[subject_id]', 'V3'
    assert_select 'select[name=?]', 'subject[subject_type]' do
      assert_select 'option[selected][value=?]', 'Vendor'
    end
  end

  def test_new_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    get :new, params: { project_id: @project.id }

    assert_response :forbidden
  end

  # Create action tests

  def test_create_with_valid_data
    @request.session[:user_id] = @user.id

    assert_difference 'Subject.count', 1 do
      post :create, params: {
        project_id: @project.id,
        subject: {
          subject_type: 'Vendor',
          subject_id: 'V10',
          name: 'New Test Vendor',
          email: 'newvendor@example.com',
          phone: '555-1234',
          uid: 'newvendor',
          location: 'New York',
          status: 'Active'
        }
      }
    end

    assert_redirected_to project_subjects_path(@project)
    assert_equal 'Successful creation.', flash[:notice]

    new_subject = Subject.find_by(subject_id: 'V10')
    assert_not_nil new_subject
    assert_equal 'New Test Vendor', new_subject.name
    assert_equal 'newvendor@example.com', new_subject.email
  end

  def test_create_with_invalid_vendor_id_format
    @request.session[:user_id] = @user.id

    assert_no_difference 'Subject.count' do
      post :create, params: {
        project_id: @project.id,
        subject: {
          subject_type: 'Vendor',
          subject_id: '123',  # Invalid: missing "V" prefix
          name: 'Invalid Vendor',
          email: 'invalid@example.com',
          status: 'Active'
        }
      }
    end

    assert_response :success  # Renders form again
    assert_select 'div#errorExplanation'
  end

  def test_create_with_missing_required_fields
    @request.session[:user_id] = @user.id

    assert_no_difference 'Subject.count' do
      post :create, params: {
        project_id: @project.id,
        subject: {
          subject_type: 'Vendor',
          subject_id: 'V20',
          name: '',  # Required field missing
          status: 'Active'
        }
      }
    end

    assert_response :success  # Renders form again
    assert_select 'div#errorExplanation'
  end

  def test_create_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    assert_no_difference 'Subject.count' do
      post :create, params: {
        project_id: @project.id,
        subject: {
          subject_type: 'Vendor',
          subject_id: 'V30',
          name: 'Unauthorized Vendor',
          status: 'Active'
        }
      }
    end

    assert_response :forbidden
  end

  # Edit action tests

  def test_edit_with_permission_shows_form
    @request.session[:user_id] = @user.id

    get :edit, params: { project_id: @project.id, id: @vendor1.id }

    assert_response :success
    assert_select 'form'
    assert_select 'input[name=?][value=?]', 'subject[name]', @vendor1.name
  end

  def test_edit_nonexistent_subject_returns_404
    @request.session[:user_id] = @user.id

    get :edit, params: { project_id: @project.id, id: 99999 }

    assert_response :not_found
  end

  def test_edit_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    get :edit, params: { project_id: @project.id, id: @vendor1.id }

    assert_response :forbidden
  end

  # Update action tests

  def test_update_with_valid_data
    @request.session[:user_id] = @user.id

    patch :update, params: {
      project_id: @project.id,
      id: @vendor1.id,
      subject: {
        name: 'Updated Vendor Name',
        email: 'updated@example.com',
        status: 'Inactive'
      }
    }

    assert_redirected_to project_subjects_path(@project)
    assert_equal 'Successful update.', flash[:notice]

    @vendor1.reload
    assert_equal 'Updated Vendor Name', @vendor1.name
    assert_equal 'updated@example.com', @vendor1.email
    assert_equal 'Inactive', @vendor1.status
  end

  def test_update_with_invalid_data
    @request.session[:user_id] = @user.id

    patch :update, params: {
      project_id: @project.id,
      id: @vendor1.id,
      subject: {
        name: ''  # Required field
      }
    }

    assert_response :success  # Renders form again
    assert_select 'div#errorExplanation'

    @vendor1.reload
    assert_equal 'Test Vendor 1', @vendor1.name  # Name unchanged
  end

  def test_update_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    patch :update, params: {
      project_id: @project.id,
      id: @vendor1.id,
      subject: { name: 'Hacked Name' }
    }

    assert_response :forbidden

    @vendor1.reload
    assert_equal 'Test Vendor 1', @vendor1.name  # Name unchanged
  end

  # Destroy action tests

  def test_destroy_with_permission_deletes_subject
    @request.session[:user_id] = @user.id

    assert_difference 'Subject.count', -1 do
      delete :destroy, params: { project_id: @project.id, id: @vendor1.id }
    end

    assert_redirected_to project_subjects_path(@project)
    assert_equal 'Successful deletion.', flash[:notice]
    assert_nil Subject.find_by(id: @vendor1.id)
  end

  def test_destroy_without_permission_is_forbidden
    @request.session[:user_id] = @user.id
    # Remove the permission
    role = Role.find(1)
    role.remove_permission! :manage_subjects

    assert_no_difference 'Subject.count' do
      delete :destroy, params: { project_id: @project.id, id: @vendor1.id }
    end

    assert_response :forbidden
    assert_not_nil Subject.find_by(id: @vendor1.id)
  end

  def test_destroy_nonexistent_subject_returns_404
    @request.session[:user_id] = @user.id

    delete :destroy, params: { project_id: @project.id, id: 99999 }

    assert_response :not_found
  end
end
