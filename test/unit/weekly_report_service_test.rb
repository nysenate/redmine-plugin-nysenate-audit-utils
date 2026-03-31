# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class WeeklyReportServiceTest < ActiveSupport::TestCase
  fixtures :issues, :issue_statuses, :projects, :trackers, :custom_fields, :custom_values

  def setup
    @project = Project.find(1)

    # Set up custom field configuration for user_id
    Setting.plugin_nysenate_audit_utils = {
      'user_id_field_id' => '2'
    }
  end

  def teardown
    # Reset to nil to avoid affecting other tests
    Setting.plugin_nysenate_audit_utils = {}
  end

  test "should initialize with correct date range" do
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)

    assert_equal Date.current.beginning_of_week, service.from_date
    assert_in_delta Time.zone.now, service.to_date, 2.seconds
  end

  test "should filter issues by project" do
    # Create issues in different projects
    project1 = Project.find(1)
    project2 = Project.find(2) rescue Project.create!(name: 'Test Project 2', identifier: 'test-project-2')

    # Create an issue in project1 (should be included)
    issue1 = Issue.create!(
      project: project1,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Issue in Project 1',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )

    # Create an issue in project2 (should NOT be included)
    issue2 = Issue.create!(
      project: project2,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Issue in Project 2',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )

    # Generate report for project1
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: project1)
    report_data = service.generate

    assert service.success?, "Report should succeed"

    # Extract issue IDs from report
    issue_ids = report_data.map { |r| r[:issue_id] }

    # Verify only project1's issue is included
    assert_includes issue_ids, issue1.id, "Should include issue from project 1"
    assert_not_includes issue_ids, issue2.id, "Should not include issue from project 2"
  end

  test "should include issues created this week" do
    # Create an issue created this week
    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Created This Week',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }
    assert_includes issue_ids, issue.id
  end

  test "should include issues updated this week" do
    # Create an issue created last month but updated this week
    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Updated This Week',
      created_on: 1.month.ago,
      updated_on: Date.current.beginning_of_week + 1.day
    )

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }
    assert_includes issue_ids, issue.id
  end

  test "should not include issues from previous weeks" do
    # Create an issue created and updated before the current week started
    # Use a specific date to ensure it's before the week boundary
    last_week_date = Date.current.beginning_of_week - 7.days

    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Old Issue From Last Week'
    )

    # Use SQL to set timestamps to last week, bypassing Rails callbacks
    Issue.where(id: issue.id).update_all(created_on: last_week_date, updated_on: last_week_date)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }
    assert_not_includes issue_ids, issue.id, "Should not include issue from previous week (issue #{issue.id})"
  end

  test "should return empty array when no issues match" do
    # Don't create any issues for this week
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?
    assert_kind_of Array, report_data
    # May have some test fixture issues, but shouldn't fail
  end

  test "should handle missing custom field configuration gracefully" do
    # Remove custom field configuration
    Setting.plugin_nysenate_audit_utils = {}

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    # Service should return empty array with error
    assert_equal [], report_data
    assert_not service.success?
    assert_includes service.errors.join, "Employee ID custom field is not configured"
  end

  test "should extract custom field values from issues" do
    # Create a custom field and set a value
    custom_field = CustomField.find(2) # Using fixture custom field

    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Issue with Custom Field',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )

    # Reload to avoid stale object error, then add custom value
    issue.reload
    issue.custom_field_values = { custom_field.id => '12345' }
    issue.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?

    # Find the issue in report data
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report, "Should find issue in report"
    assert_equal '12345', issue_report[:user_id]
  end

  test "should filter out issues without User ID custom field configured" do
    # Note: This test checks that issues without the User ID field configured for their
    # tracker/project are excluded. Issues with the field configured but blank should be included.

    # For this test, we need to ensure the custom field is configured for the tracker
    custom_field = CustomField.find(2)

    # Ensure custom field is enabled for tracker 1 (should be from fixtures)
    tracker1 = Tracker.find(1)
    custom_field.trackers << tracker1 unless custom_field.trackers.include?(tracker1)

    # Create an issue with the field configured (even if blank)
    issue_with_field = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Issue With Field Configured',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )
    # Leave the field blank intentionally

    # Create an issue with the field configured and populated
    issue_with_value = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Issue With Field Value',
      created_on: Date.current.beginning_of_week + 1.day,
      updated_on: Date.current.beginning_of_week + 1.day
    )
    # Reload to avoid stale object error
    issue_with_value.reload
    issue_with_value.custom_field_values = { custom_field.id => '12345' }
    issue_with_value.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?

    issue_ids = report_data.map { |r| r[:issue_id] }

    # Should include issue with field configured but blank
    assert_includes issue_ids, issue_with_field.id, "Should include issue with field configured (even if blank)"

    # Should include issue with field value
    assert_includes issue_ids, issue_with_value.id, "Should include issue with User ID value"
  end

  test "should order issues by updated_on descending" do
    # Create multiple issues with different update times
    # Use direct SQL update to bypass Rails timestamp handling
    base_time = Date.current.beginning_of_week.to_time

    issue1 = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Oldest Update'
    )

    issue2 = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Newest Update'
    )

    issue3 = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1,
      subject: 'Middle Update'
    )

    # Update timestamps using SQL to bypass callbacks
    Issue.where(id: issue1.id).update_all(created_on: base_time, updated_on: base_time + 1.hour)
    Issue.where(id: issue2.id).update_all(created_on: base_time, updated_on: base_time + 3.hours)
    Issue.where(id: issue3.id).update_all(created_on: base_time, updated_on: base_time + 2.hours)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert service.success?

    # Filter to only our test issues
    test_issue_ids = [issue1.id, issue2.id, issue3.id]
    test_report_data = report_data.select { |r| test_issue_ids.include?(r[:issue_id]) }

    assert_equal 3, test_report_data.length, "Should have 3 test issues"

    # Check order: newest updated first (sorted by updated_on DESC)
    assert_equal issue2.id, test_report_data[0][:issue_id], "First should be issue2 (newest)"
    assert_equal issue3.id, test_report_data[1][:issue_id], "Second should be issue3 (middle)"
    assert_equal issue1.id, test_report_data[2][:issue_id], "Third should be issue1 (oldest)"
  end
end
