# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class WeeklyReportServiceTest < ActiveSupport::TestCase
  fixtures :issues, :issue_statuses, :projects, :trackers, :custom_fields, :custom_values

  def setup
    @project = Project.find(1)

    Setting.plugin_nysenate_audit_utils = {
      'user_id_field_id' => '2'
    }
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  test "should initialize with previous sunday-to-sunday date range" do
    travel_to Time.zone.parse('2026-04-07 12:00:00') do # Tuesday
      service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)

      expected_to = Date.parse('2026-04-05').beginning_of_week(:sunday).in_time_zone
      expected_from = expected_to - 7.days

      assert_equal expected_from, service.from_date
      assert_equal expected_to, service.to_date
    end
  end

  test "should initialize with sunday-to-sunday range when today is sunday" do
    travel_to Time.zone.parse('2026-04-05 10:00:00') do # Sunday
      service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)

      expected_to = Date.parse('2026-04-05').beginning_of_week(:sunday).in_time_zone
      expected_from = expected_to - 7.days

      assert_equal expected_from, service.from_date
      assert_equal expected_to, service.to_date
    end
  end

  test "should accept custom from_date and to_date" do
    custom_from = 2.weeks.ago.beginning_of_day
    custom_to = 1.week.ago.end_of_day

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: custom_from,
      to_date: custom_to
    )

    assert_equal custom_from, service.from_date
    assert_equal custom_to, service.to_date
  end

  test "should only include closed issues" do
    close_time = 2.days.ago

    closed_issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 5, # closed
      subject: 'Closed Issue'
    )
    Issue.where(id: closed_issue.id).update_all(
      created_on: 1.week.ago,
      updated_on: close_time,
      closed_on: close_time
    )

    open_issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 1, # open/new
      subject: 'Open Issue'
    )
    Issue.where(id: open_issue.id).update_all(
      created_on: 1.week.ago,
      updated_on: 2.days.ago,
      closed_on: nil
    )

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }

    assert_includes issue_ids, closed_issue.id, "Should include closed issue"
    assert_not_includes issue_ids, open_issue.id, "Should not include open issue"
  end

  test "should filter by closed_on date range" do
    # Issue closed within range — should be included
    in_range = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 5,
      subject: 'Closed In Range'
    )
    Issue.where(id: in_range.id).update_all(
      created_on: 2.weeks.ago,
      updated_on: 2.days.ago,
      closed_on: 2.days.ago
    )

    # Issue closed before range — should NOT be included even though updated recently
    out_of_range = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 5,
      subject: 'Closed Before Range'
    )
    Issue.where(id: out_of_range.id).update_all(
      created_on: 3.weeks.ago,
      updated_on: 1.day.ago,   # recently updated but closed outside range
      closed_on: 3.weeks.ago
    )

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }

    assert_includes issue_ids, in_range.id, "Should include issue closed within range"
    assert_not_includes issue_ids, out_of_range.id, "Should not include issue closed outside range"
  end

  test "should filter issues by project" do
    project1 = Project.find(1)
    project2 = Project.find(2) rescue Project.create!(name: 'Test Project 2', identifier: 'test-project-2')

    close_time = 2.days.ago

    issue1 = Issue.create!(project: project1, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue in Project 1')
    Issue.where(id: issue1.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    issue2 = Issue.create!(project: project2, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue in Project 2')
    Issue.where(id: issue2.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: project1,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }

    assert_includes issue_ids, issue1.id
    assert_not_includes issue_ids, issue2.id
  end

  test "should return empty array when no closed issues match" do
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    assert_kind_of Array, report_data
  end

  test "should handle missing custom field configuration gracefully" do
    Setting.plugin_nysenate_audit_utils = {}

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: @project)
    report_data = service.generate

    assert_equal [], report_data
    assert_not service.success?
    assert_includes service.errors.join, "Employee ID custom field is not configured"
  end

  test "should extract user_id custom field value" do
    custom_field = CustomField.find(2)
    close_time = 2.days.ago

    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      status_id: 5,
      subject: 'Issue with User ID'
    )
    Issue.where(id: issue.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    issue.reload
    issue.custom_field_values = { custom_field.id => '12345' }
    issue.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report
    assert_equal '12345', issue_report[:user_id]
  end

  test "should include user_name in report data when configured" do
    user_name_field = IssueCustomField.create!(
      name: 'User Name',
      field_format: 'string',
      is_for_all: true,
      trackers: Tracker.all
    )
    Setting.plugin_nysenate_audit_utils = {
      'user_id_field_id' => '2',
      'user_name_field_id' => user_name_field.id.to_s
    }

    close_time = 2.days.ago
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue with User Name')
    Issue.where(id: issue.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    issue.reload
    issue.custom_field_values = { user_name_field.id => 'Jane Doe' }
    issue.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report
    assert_equal 'Jane Doe', issue_report[:user_name]
  ensure
    user_name_field&.destroy
    Setting.plugin_nysenate_audit_utils = { 'user_id_field_id' => '2' }
  end

  test "should include office in report data when configured" do
    location_field = IssueCustomField.create!(
      name: 'User Office',
      field_format: 'string',
      is_for_all: true,
      trackers: Tracker.all
    )
    Setting.plugin_nysenate_audit_utils = {
      'user_id_field_id' => '2',
      'user_location_field_id' => location_field.id.to_s
    }

    close_time = 2.days.ago
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue with Office')
    Issue.where(id: issue.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    issue.reload
    issue.custom_field_values = { location_field.id => 'Senate Office A' }
    issue.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report
    assert_equal 'Senate Office A', issue_report[:office]
  ensure
    location_field&.destroy
    Setting.plugin_nysenate_audit_utils = { 'user_id_field_id' => '2' }
  end

  test "should include closed_on in report data" do
    close_time = 2.days.ago
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue with Close Date')
    Issue.where(id: issue.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report
    assert_in_delta close_time, issue_report[:closed_on], 1.second
  end

  test "should include created_on as open date in report data" do
    create_time = 5.days.ago
    close_time = 2.days.ago
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue with Open Date')
    Issue.where(id: issue.id).update_all(created_on: create_time, updated_on: close_time, closed_on: close_time)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_report = report_data.find { |r| r[:issue_id] == issue.id }
    assert_not_nil issue_report
    assert_in_delta create_time, issue_report[:created_on], 1.second
  end

  test "should filter out issues without User ID custom field configured" do
    custom_field = CustomField.find(2)
    tracker1 = Tracker.find(1)
    custom_field.trackers << tracker1 unless custom_field.trackers.include?(tracker1)

    close_time = 2.days.ago

    issue_with_field = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue With Field Configured')
    Issue.where(id: issue_with_field.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)

    issue_with_value = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Issue With Field Value')
    Issue.where(id: issue_with_value.id).update_all(created_on: 1.week.ago, updated_on: close_time, closed_on: close_time)
    issue_with_value.reload
    issue_with_value.custom_field_values = { custom_field.id => '12345' }
    issue_with_value.save!

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?
    issue_ids = report_data.map { |r| r[:issue_id] }

    assert_includes issue_ids, issue_with_field.id
    assert_includes issue_ids, issue_with_value.id
  end

  test "should order issues by closed_on descending" do
    base_time = 5.days.ago

    issue1 = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Oldest Closed')
    issue2 = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Newest Closed')
    issue3 = Issue.create!(project: @project, tracker_id: 1, author_id: 1, status_id: 5, subject: 'Middle Closed')

    Issue.where(id: issue1.id).update_all(created_on: base_time, updated_on: base_time + 1.hour, closed_on: base_time + 1.hour)
    Issue.where(id: issue2.id).update_all(created_on: base_time, updated_on: base_time + 3.hours, closed_on: base_time + 3.hours)
    Issue.where(id: issue3.id).update_all(created_on: base_time, updated_on: base_time + 2.hours, closed_on: base_time + 2.hours)

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: 1.week.ago,
      to_date: Time.zone.now
    )
    report_data = service.generate

    assert service.success?

    test_issue_ids = [issue1.id, issue2.id, issue3.id]
    test_report_data = report_data.select { |r| test_issue_ids.include?(r[:issue_id]) }

    assert_equal 3, test_report_data.length
    assert_equal issue2.id, test_report_data[0][:issue_id], "First should be issue2 (newest closed)"
    assert_equal issue3.id, test_report_data[1][:issue_id], "Second should be issue3 (middle closed)"
    assert_equal issue1.id, test_report_data[2][:issue_id], "Third should be issue1 (oldest closed)"
  end
end
