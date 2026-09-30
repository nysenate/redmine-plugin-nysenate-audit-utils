# frozen_string_literal: true

require File.expand_path('../../test_helper', __dir__)

module NysenateAuditUtils
  module Reporting
    class TriennialAuditFlagServiceTest < ActiveSupport::TestCase
      fixtures :projects, :trackers, :projects_trackers, :issue_statuses, :users, :enumerations,
               :members, :member_roles, :roles

      def setup
        @field = IssueCustomField.create!(
          name: 'Triennial Selected', field_format: 'list', possible_values: %w[No 2022 2025],
          default_value: 'No', is_for_all: true, trackers: Tracker.where(id: [1, 2])
        )
        Setting.plugin_nysenate_audit_utils = {
          'selected_for_audit_field_id' => @field.id.to_s,
          'triennial_audit_sources' => [
            { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' },
            { 'project_id' => '1', 'tracker_id' => '3', 'mapping_mode' => 'tracker', 'code' => 'SUPA' }
          ]
        }
        @user = User.find(1)
      end

      def teardown
        Setting.plugin_nysenate_audit_utils = {}
      end

      def make_issue(tracker_id: 1, project_id: 1)
        Issue.create!(project_id: project_id, tracker_id: tracker_id, author_id: 1, status_id: 1,
                      subject: 'Triennial flag')
      end

      def flag(ids, value)
        TriennialAuditFlagService.new(user: @user).flag(ids, value)
      end

      test 'sets the field and journals the change without notifying' do
        issue = make_issue

        result = flag([issue.id.to_s], '2025')

        assert_equal [issue.id], result.flagged
        assert_equal '2025', issue.reload.custom_field_value(@field)
        journal = issue.journals.last
        assert_equal @user, journal.user
        assert_equal [['No', '2025']], journal.details.map { |d| [d.old_value, d.value] }
      end

      test 'does not send notifications' do
        issue = make_issue
        ActionMailer::Base.deliveries.clear

        with_settings notified_events: %w[issue_updated] do
          flag([issue.id], '2025')
        end

        assert_empty ActionMailer::Base.deliveries
      end

      test 'skips tickets that already have the value' do
        issue = make_issue
        flag([issue.id], '2025')

        result = flag([issue.id], '2025')

        assert_equal [issue.id], result.unchanged
        assert_empty result.flagged
        assert_equal 1, issue.journals.count
      end

      test 'No clears a flag' do
        issue = make_issue
        flag([issue.id], '2025')

        flag([issue.id], 'No')

        assert_equal 'No', issue.reload.custom_field_value(@field)
      end

      test 'refuses tickets outside the configured sources' do
        outside = make_issue(tracker_id: 2)

        result = flag([outside.id], '2025')

        assert_equal [{ issue_id: outside.id, message: 'not in a Triennial Audit source' }], result.failed
        assert_equal 'No', outside.reload.custom_field_value(@field)
      end

      test 'reports tickets whose tracker lacks the field' do
        issue = make_issue(tracker_id: 3)

        result = flag([issue.id], '2025')

        assert_match(/Triennial Selected is not enabled for .* \/ Support request/, result.failed.first[:message])
      end

      test 'a missing ticket blocks the whole submission' do
        issue = make_issue

        result = flag([issue.id, 999_999], '2025')

        assert result.permission_denied?
        assert_empty result.flagged
        assert_equal [{ issue_id: 999_999, message: "ticket not found or you don't have permission to view it" }],
                     result.failed
        assert_equal 'No', issue.reload.custom_field_value(@field)
      end

      test 'a ticket the user cannot view blocks the whole submission' do
        visible = make_issue
        hidden = Issue.create!(project_id: 1, tracker_id: 1, author_id: 1, status_id: 1, subject: 'Private',
                               is_private: true)

        result = TriennialAuditFlagService.new(user: User.find(3)).flag([visible.id, hidden.id], '2025')

        assert result.permission_denied?
        assert_equal [hidden.id], result.failed.pluck(:issue_id)
        assert_equal 'No', visible.reload.custom_field_value(@field)
      end

      test 'a ticket the user cannot edit blocks the whole submission' do
        issue = make_issue
        Role.find(2).remove_permission!(:edit_issues)

        result = TriennialAuditFlagService.new(user: User.find(3)).flag([issue.id], '2025')

        assert result.permission_denied?
        assert_equal [{ issue_id: issue.id, message: "you don't have permission to edit it" }], result.failed
        assert_equal 'No', issue.reload.custom_field_value(@field)
      end

      test 'a user who can view and edit can flag' do
        issue = make_issue

        result = TriennialAuditFlagService.new(user: User.find(3)).flag([issue.id], '2025')

        assert_equal [issue.id], result.flagged
      end

      test 'rejects values the field does not offer' do
        assert_raises(ArgumentError) { flag([make_issue.id], '1999') }
      end

      test 'raises when the field is not configured' do
        Setting.plugin_nysenate_audit_utils = {}

        assert_raises(ArgumentError) { flag([1], '2025') }
      end

      test 'flag_values lists audit years then No, and default_value prefers the current year' do
        assert_equal %w[2022 2025 No], TriennialAuditFlagService.flag_values
        travel_to(Date.new(2025, 6, 1)) { assert_equal '2025', TriennialAuditFlagService.default_value }
        travel_to(Date.new(2027, 6, 1)) { assert_equal '2025', TriennialAuditFlagService.default_value }
        travel_to(Date.new(2022, 6, 1)) { assert_equal '2022', TriennialAuditFlagService.default_value }
      end
    end
  end
end
