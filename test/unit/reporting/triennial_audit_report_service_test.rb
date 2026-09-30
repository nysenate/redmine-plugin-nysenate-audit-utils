# frozen_string_literal: true

require File.expand_path('../../test_helper', __dir__)

module NysenateAuditUtils
  module Reporting
    class TriennialAuditReportServiceTest < ActiveSupport::TestCase
      fixtures :projects, :trackers, :projects_trackers, :issue_statuses, :users, :enumerations

      def setup
        @selected = IssueCustomField.create!(
          name: 'Triennial Selected', field_format: 'list', possible_values: %w[No 2025],
          is_for_all: true, trackers: Tracker.all
        )
        Setting.plugin_nysenate_audit_utils = {
          'selected_for_audit_field_id' => @selected.id.to_s,
          'triennial_audit_sources' => [
            { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' },
            { 'project_id' => '1', 'tracker_id' => '2', 'mapping_mode' => 'tracker', 'code' => '' }
          ]
        }
        @from = Time.zone.parse('2026-01-01')
        @to = Time.zone.parse('2026-01-31')
      end

      def teardown
        Setting.plugin_nysenate_audit_utils = {}
      end

      def make_issue(tracker_id: 1, project_id: 1, created_on: Time.zone.parse('2026-01-15 10:00'), **attrs)
        issue = Issue.create!(project_id: project_id, tracker_id: tracker_id, author_id: 1, status_id: 1,
                              subject: "Triennial #{tracker_id}", **attrs)
        Issue.where(id: issue.id).update_all(created_on: created_on)
        issue.reload
      end

      def generate(from: @from, to: @to, user: User.find(1))
        service = TriennialAuditReportService.new(from_date: from, to_date: to, user: user)
        [service, service.generate]
      end

      test 'lists tickets from every configured source in the open-date window' do
        bug = make_issue
        feature = make_issue(tracker_id: 2)
        make_issue(tracker_id: 3) # tracker not configured
        make_issue(project_id: 2) # project not configured

        _service, rows = generate
        assert_equal [bug.id, feature.id].sort, rows.pluck(:issue_id).sort
      end

      # dlopper (user 3) is a Developer on project 1 only; Developer's issue
      # visibility is "All non private issues".
      def developer
        User.find(3)
      end

      test 'an admin sees everything with no permission errors' do
        make_issue(is_private: true)
        make_issue(project_id: 2)
        Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
          'triennial_audit_sources' => [
            { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker' },
            { 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'tracker' }
          ]
        )

        service, rows = generate
        assert_equal 2, rows.size
        assert_empty service.permission_errors
      end

      test 'lists a project the user cannot view issues in, once per project' do
        Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
          'triennial_audit_sources' => [
            { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker' },
            { 'project_id' => '2', 'tracker_id' => '1', 'mapping_mode' => 'tracker' },
            { 'project_id' => '2', 'tracker_id' => '2', 'mapping_mode' => 'tracker' }
          ]
        )

        service, = generate(user: developer)
        assert_equal ["View issues in #{Project.find(2).name}"], service.permission_errors
      end

      test 'lists a tracker the user cannot view issues for' do
        role = Role.find(2)
        role.set_permission_trackers(:view_issues, [1])
        role.save!

        service, = generate(user: developer)
        assert_equal ["View issues for the Feature request tracker in #{Project.find(1).name}"],
                     service.permission_errors
      end

      test 'lists issues visibility when some tickets in the window are hidden' do
        make_issue
        make_issue(is_private: true)
        make_issue(is_private: true, created_on: Time.zone.parse('2025-06-01')) # outside the window

        service, rows = generate(user: developer)
        assert_equal 1, rows.size
        assert_equal ["Issues visibility \"All issues\" in #{Project.find(1).name} " \
                      '(your current visibility hides 1 Bug ticket in this date range)'], service.permission_errors
      end

      test 'rows say whether the user can edit the ticket' do
        make_issue
        _service, rows = generate(user: developer)
        assert rows.first[:editable]

        Role.find(2).remove_permission!(:edit_issues)
        _service, rows = generate(user: developer)
        assert_not rows.first[:editable]
      end

      test 'window includes the whole From and To days' do
        first = make_issue(created_on: Time.zone.parse('2026-01-01 00:00'))
        last = make_issue(created_on: Time.zone.parse('2026-01-31 23:59'))
        make_issue(created_on: Time.zone.parse('2025-12-31 23:59'))
        make_issue(created_on: Time.zone.parse('2026-02-01 00:00'))

        _service, rows = generate
        assert_equal [first.id, last.id].sort, rows.pluck(:issue_id).sort
      end

      test 'builds the row fields' do
        issue = make_issue(custom_field_values: { @selected.id => '2025' })
        Issue.where(id: issue.id).update_all(closed_on: Time.zone.parse('2026-01-20'))

        row = generate.last.first
        assert_equal 'BUGA', row[:request_code]
        assert_equal issue.subject, row[:subject]
        assert_equal Date.new(2026, 1, 15), row[:open_date].to_date
        assert_equal Date.new(2026, 1, 20), row[:closed_date].to_date
        assert_equal IssueStatus.find(1).name, row[:status]
        assert_equal '2025', row[:selected_for_audit]
      end

      test 'a ticket without a resolved code still appears with a blank code' do
        issue = make_issue(tracker_id: 2)

        row = generate.last.find { |r| r[:issue_id] == issue.id }
        assert_nil row[:request_code]
      end

      test 'a missing source is reported without dropping the others' do
        Setting.plugin_nysenate_audit_utils = Setting.plugin_nysenate_audit_utils.merge(
          'triennial_audit_sources' => [
            { 'project_id' => '999', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'X' },
            { 'project_id' => '1', 'tracker_id' => '1', 'mapping_mode' => 'tracker', 'code' => 'BUGA' }
          ]
        )
        issue = make_issue

        service, rows = generate
        assert_equal [issue.id], rows.pluck(:issue_id)
        assert_equal ['Source project #999 / Bug: the project no longer exists.'], service.errors
      end

      test 'a source whose query raises is reported without dropping the others' do
        issue = make_issue
        TriennialAuditConfiguration.stubs(:resolve_code).returns('BUGA')
        TriennialAuditConfiguration.stubs(:resolve_code).with { |i| i.tracker_id == 2 }.raises(StandardError, 'boom')
        make_issue(tracker_id: 2)

        service, rows = generate
        assert_equal [issue.id], rows.pluck(:issue_id)
        assert_equal ["Source #{Project.find(1).name} / Feature request: boom"], service.errors
      end

      test 'no configured sources yields no rows and no errors' do
        Setting.plugin_nysenate_audit_utils = {}
        make_issue

        service, rows = generate
        assert_empty rows
        assert service.success?
      end

      test 'default window is the trailing three years ending today' do
        travel_to Time.zone.parse('2026-09-29 12:00') do
          service = TriennialAuditReportService.new
          assert_equal Date.new(2023, 9, 30), service.from_date.to_date
          assert_equal Date.new(2026, 9, 29), service.to_date.to_date
        end
      end

      test 'group_by_code sorts by code then ticket, with unresolved codes last' do
        rows = [
          { request_code: 'B', issue_id: 5 }, { request_code: nil, issue_id: 1 },
          { request_code: 'A', issue_id: 9 }, { request_code: 'B', issue_id: 2 }
        ]

        groups = TriennialAuditReportService.group_by_code(rows)
        assert_equal ['A', 'B', nil], groups.map(&:first)
        assert_equal [2, 5], groups[1].last.pluck(:issue_id)
      end

      FILTER_ROWS = [
        { request_code: 'AIXA', subject: 'Add AIX account', issue_id: 101, project_id: 1, tracker_id: 1,
          selected_for_audit: '2025' },
        { request_code: 'AIXI', subject: 'Remove AIX account', issue_id: 102, project_id: 1, tracker_id: 1,
          selected_for_audit: 'No' },
        { request_code: 'NEW', subject: 'New payroll process', issue_id: 203, project_id: 2, tracker_id: 3 },
        { request_code: nil, subject: 'Uncoded request', issue_id: 204, project_id: 2, tracker_id: 3 }
      ].freeze

      def filtered_ids(**filters)
        TriennialAuditReportService.filter_rows(FILTER_ROWS, **filters).pluck(:issue_id)
      end

      test 'filter_rows filters by source and code, ignoring blanks' do
        assert_equal [101, 102, 203, 204], filtered_ids(source: '', code: nil, search: '')
        assert_equal [203, 204], filtered_ids(source: '2-3')
        assert_equal [102], filtered_ids(code: 'AIXI')
        assert_equal [204], filtered_ids(code: TriennialAuditReportService::NO_CODE)
        assert_empty filtered_ids(source: '2-3', code: 'AIXA')
      end

      test 'filter_rows filters by Selected for Audit value, with No matching unset tickets' do
        assert_equal [101], filtered_ids(selected: '2025')
        assert_equal [102, 203, 204], filtered_ids(selected: 'No')
        assert_empty filtered_ids(selected: '2025', code: 'AIXI')
      end

      test 'search matches code or subject substrings, case-insensitively' do
        assert_equal [101, 102], filtered_ids(search: 'aix')
        assert_equal [203], filtered_ids(search: 'PAYROLL')
      end

      test 'search matches an exact ticket number, with or without #' do
        assert_equal [203], filtered_ids(search: '203')
        assert_equal [203], filtered_ids(search: '#203')
        assert_empty filtered_ids(search: '20')
      end
    end
  end
end
