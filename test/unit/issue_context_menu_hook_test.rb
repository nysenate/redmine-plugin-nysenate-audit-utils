require File.expand_path('../../test_helper', __FILE__)

class IssueContextMenuHookTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :enabled_modules, :roles, :members, :member_roles

  def setup
    @issue1 = Issue.find(1)
    @issue2 = Issue.find(2)
    @issue3 = Issue.find(3)
    User.current = User.find(1)
    
    # Access the singleton instance
    @hook = IssueContextMenuHook.instance
  end

  def test_view_issues_context_menu_end_with_multiple_issues
    context = { issues: [@issue1, @issue2, @issue3] }
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_not_equal '', result
    assert_match /<li>/, result
    assert_match /Create Multi Packet/, result
    assert_match /create_multi_packet/, result
    assert_match /icon-package/, result
    assert_match /confirm/, result
  end

  def test_view_issues_context_menu_end_with_single_issue
    context = { issues: [@issue1] }
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_not_equal '', result
    assert_match /<li>/, result
    assert_match /Create Packet/, result
    assert_match /create_packet/, result
    assert_match /icon-package/, result
    assert_no_match /confirm/, result
  end

  def test_view_issues_context_menu_end_with_no_issues
    context = { issues: [] }
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_equal '', result
  end

  def test_view_issues_context_menu_end_with_nil_issues
    context = { issues: nil }
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_equal '', result
  end

  def test_view_issues_context_menu_end_with_empty_context
    context = {}
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_equal '', result
  end

  def test_view_issues_context_menu_end_with_permission_denied
    # Create a user with no project memberships
    user_no_permission = User.create!(
      login: "noaccess_hook",
      firstname: "No",
      lastname: "Access Hook",
      mail: "noaccess_hook@example.com",
      status: User::STATUS_ACTIVE,
      admin: false
    )
    
    # Ensure the project is not public
    @issue1.project.update!(is_public: false)
    
    # Switch to a user without view permissions
    User.current = user_no_permission
    context = { issues: [@issue1, @issue2] }
    
    result = @hook.view_issues_context_menu_end(context)
    
    assert_equal '', result
  end
end