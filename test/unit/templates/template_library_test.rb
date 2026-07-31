# frozen_string_literal: true

require File.expand_path('../../test_helper', __dir__)

class TemplateLibraryTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :users, :roles, :members, :member_roles, :enabled_modules

  Library = NysenateAuditUtils::Templates::TemplateLibrary

  def setup
    User.current = User.find(1) # admin -> all issues visible
    @project = Project.find(1)
    @tracker = @project.trackers.first
    Setting.plugin_nysenate_audit_utils = { 'templates_project_id' => @project.id.to_s }
  end

  def teardown
    User.current = nil
  end

  def create_issue(subject, project: @project, closed: false)
    status = IssueStatus.where(is_closed: closed).first
    Issue.create!(project: project, tracker: @tracker, author: User.find(1),
                  status: status, priority: IssuePriority.first, subject: subject)
  end

  def test_templates_lists_open_marked_issues_with_split_label_and_subject
    issue = create_issue('USRA: <TEMPLATE> Create account for <Account Holder Name>')

    entry = Library.templates.find { |e| e[:id] == issue.id }
    assert entry, 'expected the marked issue to be listed'
    assert_equal 'USRA:', entry[:label]
    assert_equal 'Create account for <Account Holder Name>', entry[:subject_template]
    # display combines the label and the subject template for the menu text.
    assert_equal 'USRA: Create account for <Account Holder Name>', entry[:display]
  end

  def test_templates_excludes_issues_without_the_marker
    create_issue('Just a regular ticket, no marker')
    assert_empty Library.templates
  end

  def test_templates_excludes_closed_issues
    create_issue('SFSS: <TEMPLATE> Reset password', closed: true)
    assert_empty Library.templates
  end

  def test_templates_are_sorted_by_label_case_insensitively
    create_issue('WEBA: <TEMPLATE> last')
    create_issue('aixa: <TEMPLATE> first')
    create_issue('SFSS: <TEMPLATE> middle')

    labels = Library.templates.pluck(:label)
    assert_equal labels.sort_by(&:downcase), labels
  end

  def test_templates_empty_when_no_project_configured
    Setting.plugin_nysenate_audit_utils = { 'templates_project_id' => nil }
    assert_empty Library.templates
  end

  def test_find_returns_the_eligible_template_for_int_or_string_id
    issue = create_issue('USRA: <TEMPLATE> x')
    assert_equal issue, Library.find(issue.id)
    assert_equal issue, Library.find(issue.id.to_s)
  end

  def test_find_rejects_an_issue_outside_the_templates_project
    other = Project.find(2)
    other.trackers << @tracker unless other.trackers.include?(@tracker)
    issue = create_issue('USRA: <TEMPLATE> x', project: other)

    assert_nil Library.find(issue.id), 'issue in a different project must not be copyable'
  end

  def test_find_rejects_closed_or_unmarked_issues
    closed = create_issue('USRA: <TEMPLATE> x', closed: true)
    unmarked = create_issue('no marker')

    assert_nil Library.find(closed.id)
    assert_nil Library.find(unmarked.id)
  end

  def test_find_with_blank_id_returns_nil
    assert_nil Library.find(nil)
    assert_nil Library.find('')
  end

  def test_available_reflects_project_and_templates
    Setting.plugin_nysenate_audit_utils = { 'templates_project_id' => nil }
    assert_not Library.available?

    Setting.plugin_nysenate_audit_utils = { 'templates_project_id' => @project.id.to_s }
    assert_not Library.available?, 'no templates yet'

    create_issue('USRA: <TEMPLATE> x')
    assert Library.available?
  end
end
