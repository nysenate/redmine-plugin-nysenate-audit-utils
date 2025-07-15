# frozen_string_literal: true

require_relative '../test_helper'

class PacketCreationViewListenerTest < PacketCreationTestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses, :trackers,
           :projects_trackers, :enabled_modules

  def setup
    super
    @listener = PacketCreationViewListener.instance
    @project = Project.find(1)
    @issue = Issue.find(1)
    @user = User.find(1)
  end

  def test_view_issues_show_description_bottom_with_permission
    User.current = @user
    
    # Enable module and grant permission
    enable_packet_creation_module(@project)
    grant_packet_creation_permission(Role.find(1))
    
    context = { issue: @issue }
    result = @listener.view_issues_show_description_bottom(context)
    
    assert_not_empty result
    assert_match /Create Packet/, result
    assert_match /create_packet/, result
    assert_match /icon-package/, result
  end

  def test_view_issues_show_description_bottom_without_permission
    # Use a non-admin user (user 2)
    User.current = User.find(2)
    
    # Don't grant permission
    enable_packet_creation_module(@project)
    
    context = { issue: @issue }
    result = @listener.view_issues_show_description_bottom(context)
    
    assert_empty result
  end

  def test_view_issues_show_description_bottom_module_not_enabled
    # Use a non-admin user (user 2)
    User.current = User.find(2)
    
    # Grant permission but don't enable module
    grant_packet_creation_permission(Role.find(1))
    
    context = { issue: @issue }
    result = @listener.view_issues_show_description_bottom(context)
    
    assert_empty result
  end

  def test_view_issues_show_description_bottom_no_issue
    User.current = @user
    
    enable_packet_creation_module(@project)
    grant_packet_creation_permission(Role.find(1))
    
    context = {}
    result = @listener.view_issues_show_description_bottom(context)
    
    assert_empty result
  end

  def test_view_issues_show_description_bottom_anonymous_user
    User.current = User.anonymous
    
    enable_packet_creation_module(@project)
    
    context = { issue: @issue }
    result = @listener.view_issues_show_description_bottom(context)
    
    assert_empty result
  end

  def test_button_includes_proper_attributes
    User.current = @user
    
    enable_packet_creation_module(@project)
    grant_packet_creation_permission(Role.find(1))
    
    context = { issue: @issue }
    result = @listener.view_issues_show_description_bottom(context)
    
    # Check for proper link attributes
    assert_match /method.*post/, result
    assert_match /class.*icon.*icon-package/, result
    assert_match /title.*Create Packet/, result
    assert_match /href.*create_packet/, result
  end

  def teardown
    User.current = nil
    super
  end
end