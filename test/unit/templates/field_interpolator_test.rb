# frozen_string_literal: true

require File.expand_path('../../test_helper', __dir__)

class FieldInterpolatorTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :users, :roles, :members, :member_roles, :enabled_modules

  Interpolator = NysenateAuditUtils::Templates::FieldInterpolator

  def setup
    User.current = User.find(1)
    @project = Project.find(1)
    @tracker = @project.trackers.first
    @fields = setup_standard_bachelp_fields(@tracker)
    @requested_by = create_user_field('Requested By', multiple: false)
    @authorizing  = create_user_field('Authorizing User(s)', multiple: true)
  end

  def teardown
    User.current = nil
  end

  def create_user_field(name, multiple:)
    field = IssueCustomField.find_by(name: name) ||
            IssueCustomField.create!(name: name, field_format: 'user', multiple: multiple, is_for_all: true)
    @tracker.custom_fields << field unless @tracker.custom_fields.include?(field)
    field
  end

  def build_issue(values = {})
    issue = Issue.new(project: @project, tracker: @tracker, author: User.find(1),
                      status: IssueStatus.first, priority: IssuePriority.first, subject: 'x')
    issue.custom_field_values = values
    issue
  end

  def test_replaces_a_token_matching_a_field_name
    issue = build_issue(@fields[:user_name].id => 'Doe, John')
    assert_equal 'Hello Doe, John', Interpolator.interpolate('Hello <Account Holder Name>', issue)
  end

  def test_leaves_unmatched_tokens_untouched
    issue = build_issue(@fields[:user_name].id => 'Doe, John')
    assert_equal 'Mirror <existing user (name / userID)>',
                 Interpolator.interpolate('Mirror <existing user (name / userID)>', issue)
  end

  def test_mixes_matched_and_unmatched_tokens
    issue = build_issue(@fields[:user_name].id => 'Doe, John', @fields[:user_uid].id => 'jdoe')
    template = 'For <Account Holder Name> / <Account Holder UID> mirror <existing user>'
    assert_equal 'For Doe, John / jdoe mirror <existing user>',
                 Interpolator.interpolate(template, issue)
  end

  def test_matched_but_empty_field_replaces_with_empty_string
    issue = build_issue(@fields[:user_name].id => 'Doe, John') # email left blank
    assert_equal 'Email: ', Interpolator.interpolate('Email: <Account Holder Email>', issue)
  end

  def test_user_field_renders_the_user_name
    issue = build_issue(@requested_by.id => User.find(2).id.to_s)
    assert_equal "By #{User.find(2).name}", Interpolator.interpolate('By <Requested By>', issue)
  end

  def test_multi_valued_user_field_joins_names
    issue = build_issue(@authorizing.id => [User.find(2).id.to_s, User.find(3).id.to_s])
    expected = [User.find(2), User.find(3)].sort.map(&:name).join(', ')
    assert_equal expected, Interpolator.interpolate('<Authorizing User(s)>', issue)
  end

  def test_blank_text_returns_empty_string
    assert_equal '', Interpolator.interpolate('', build_issue)
    assert_equal '', Interpolator.interpolate(nil, build_issue)
  end
end
