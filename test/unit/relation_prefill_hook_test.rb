# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class RelationPrefillHookTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :issues,
           :issue_statuses, :enumerations, :trackers, :projects_trackers,
           :enabled_modules, :versions

  def setup
    User.current = User.find(1) # admin sees all issues
    @hook = NysenateAuditUtils::RelationPrefillHook.instance
    @new_issue = Issue.generate!
    @target = Issue.find(2)
  end

  # Build a stub controller exposing params and a flash hash, like the real one.
  def controller_with(params)
    flash = {}
    controller = mock('controller')
    controller.stubs(:params).returns(ActionController::Parameters.new(params))
    controller.stubs(:flash).returns(flash)
    [controller, flash]
  end

  def run_after_save(params)
    controller, flash = controller_with(params)
    @hook.controller_issues_new_after_save(controller: controller, issue: @new_issue)
    flash
  end

  test "creates a relates relation to the granting issue by default" do
    assert_difference 'IssueRelation.count', 1 do
      run_after_save(related_issue_id: @target.id.to_s)
    end

    relation = IssueRelation.where(issue_from_id: @new_issue.id).last ||
               IssueRelation.where(issue_to_id: @new_issue.id).last
    assert_equal IssueRelation::TYPE_RELATES, relation.relation_type
    assert_includes [relation.issue_from_id, relation.issue_to_id], @target.id
  end

  test "honors an overridden relation type" do
    assert_difference 'IssueRelation.count', 1 do
      run_after_save(related_issue_id: @target.id.to_s,
                     related_relation_type: IssueRelation::TYPE_BLOCKS)
    end

    relation = IssueRelation.where(issue_from_id: @new_issue.id, issue_to_id: @target.id).last
    assert_equal IssueRelation::TYPE_BLOCKS, relation.relation_type
  end

  test "skips and warns when the related issue is not found" do
    flash = nil
    assert_no_difference 'IssueRelation.count' do
      flash = run_after_save(related_issue_id: '999999')
    end
    assert flash[:warning].present?
  end

  test "does nothing when no related_issue_id is given" do
    flash = nil
    assert_no_difference 'IssueRelation.count' do
      flash = run_after_save({})
    end
    assert_nil flash[:warning]
  end
end
