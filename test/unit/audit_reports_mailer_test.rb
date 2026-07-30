# frozen_string_literal: true

require_relative '../test_helper'

class AuditReportsMailerTest < ActiveSupport::TestCase
  include Redmine::I18n

  def setup
    ActionMailer::Base.deliveries.clear
    Setting.plain_text_mail = '0'
    Setting.default_language = 'en'
  end

  XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

  # Return the single .xlsx attachment on a mail, asserting exactly one exists.
  # Reports email an Excel workbook only (CSV export was retired from emails).
  def xlsx_attachment(mail)
    attachment_with_ext(mail, '.xlsx')
  end

  def attachment_with_ext(mail, ext)
    matches = mail.attachments.select { |a| a.filename.to_s.end_with?(ext) }
    assert_equal 1, matches.size, "expected exactly one #{ext} attachment"
    matches.first
  end

  def test_daily_report_generates_email
    report_data = [
      {
        employee_name: 'John Doe',
        account_statuses: [{ request_code: 'OAA' }],
        open_requests: [],
        status_changes: [{ code: 'APP', notes: nil }],
        phone_number: '555-1234',
        office: 'Test Office',
        office_location: 'Albany',
        employee_id: '12345',
        post_date: Date.parse('2026-03-01')
      }
    ]
    from_date = Time.zone.parse('2026-03-01 00:00:00')
    to_date = Time.zone.parse('2026-03-01 23:59:59')

    mail = AuditReportsMailer.daily_report('user@example.com', report_data, from_date, to_date)

    assert_equal ['user@example.com'], mail.to
    assert_match /Daily Audit Report/, mail.subject
    assert_match /2026-03-01/, mail.subject
    assert_equal 1, mail.attachments.size
    xlsx = xlsx_attachment(mail)
    assert_match /daily_report.*\.xlsx/, xlsx.filename
    assert_equal 'PK', xlsx.body.decoded[0, 2]
    # Check HTML part for content
    assert_match /Employees with Status Changes/, mail.html_part.body.to_s
    assert_match /1/, mail.html_part.body.to_s
  end

  def test_daily_report_multiple_recipients
    report_data = []
    from_date = Time.zone.parse('2026-03-01 00:00:00')
    to_date = Time.zone.parse('2026-03-01 23:59:59')

    recipients = ['user1@example.com', 'user2@example.com']
    mail = AuditReportsMailer.daily_report(recipients, report_data, from_date, to_date)

    assert_equal recipients, mail.to
  end

  def test_weekly_report_generates_email
    report_data = [
      {
        issue_id: 1,
        subject: 'Test Issue',
        status: 'Open',
        user_id: '12345',
        user_uid: 'jdoe',
        request_code: 'OAA',
        updated_on: Time.zone.parse('2026-03-01 10:00:00'),
        created_on: Time.zone.parse('2026-03-01 09:00:00')
      }
    ]
    from_date = Date.parse('2026-03-01')
    to_date = Time.zone.parse('2026-03-07 23:59:59')

    mail = AuditReportsMailer.weekly_report('user@example.com', report_data, from_date, to_date)

    assert_equal ['user@example.com'], mail.to
    assert_match /Weekly Audit Report/, mail.subject
    assert_match /Week of 2026-03-01/, mail.subject
    assert_equal 1, mail.attachments.size
    assert_match /weekly_report.*\.xlsx/, xlsx_attachment(mail).filename
    # Check HTML part for content
    assert_match /Active Tickets/, mail.html_part.body.to_s
    assert_match /1/, mail.html_part.body.to_s
  end

  def test_monthly_report_current_mode_generates_email
    report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        employee_uid: 'jdoe',
        account_type: 'Oracle',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.parse('2026-01-15'),
        request_code: 'OAA',
        issue_id: 100
      }
    ]
    target_system = 'Oracle / SFMS'
    mode = 'current'
    as_of_time = Time.current

    mail = AuditReportsMailer.monthly_report(
      'user@example.com',
      report_data,
      target_system,
      mode,
      as_of_time
    )

    assert_equal ['user@example.com'], mail.to
    assert_match /Monthly Audit Report/, mail.subject
    assert_match /Oracle \/ SFMS/, mail.subject
    assert_match /Current State/, mail.subject
    assert_equal 1, mail.attachments.size
    assert_match(/monthly_report_oracle-sfms_#{Date.current.strftime('%Y%m%d')}\.xlsx/, xlsx_attachment(mail).filename)
    # Check HTML part for content
    assert_match /Total Accounts/, mail.html_part.body.to_s
    assert_match /1/, mail.html_part.body.to_s
    assert_match /Current State/, mail.html_part.body.to_s
  end

  def test_monthly_report_monthly_mode_generates_email
    report_data = [
      {
        employee_id: '12345',
        employee_name: 'John Doe',
        employee_uid: 'jdoe',
        account_type: 'AIX',
        status: 'active',
        account_action: 'Add',
        closed_on: Date.parse('2026-01-15'),
        request_code: 'AAA',
        issue_id: 100
      }
    ]
    target_system = 'AIX'
    mode = 'monthly'
    selected_month_num = 1
    selected_year = 2026
    as_of_time = Date.new(2026, 1, 1).beginning_of_month.in_time_zone

    mail = AuditReportsMailer.monthly_report(
      'user@example.com',
      report_data,
      target_system,
      mode,
      as_of_time,
      selected_month_num,
      selected_year
    )

    assert_equal ['user@example.com'], mail.to
    assert_match /Monthly Audit Report/, mail.subject
    assert_match /AIX/, mail.subject
    assert_match /January 2026/, mail.subject
    assert_equal 1, mail.attachments.size
    assert_match /monthly_report_aix_202601\.xlsx/, xlsx_attachment(mail).filename
    # Check HTML part for content
    assert_match /Historical Snapshot/, mail.html_part.body.to_s
    assert_match /January 2026/, mail.html_part.body.to_s
  end

  def test_all_systems_monthly_report_current_mode
    reports_by_system = {
      'Oracle / SFMS' => [
        { user_id: '111', user_name: 'Alice', user_type: 'Employee', user_uid: 'alice', status: 'active', account_action: 'Add', closed_on: Date.parse('2026-03-01'), request_code: 'OAA',
issue_id: 10 }
      ],
      'AIX' => [
        { user_id: '222', user_name: 'Bob', user_type: 'Employee', user_uid: 'bob', status: 'inactive', account_action: 'Delete', closed_on: Date.parse('2026-02-15'), request_code: 'AAD',
issue_id: 20 }
      ]
    }
    mode = 'current'
    as_of_time = Time.current

    mail = AuditReportsMailer.all_systems_monthly_report('user@example.com', reports_by_system, mode, as_of_time)

    assert_equal ['user@example.com'], mail.to
    assert_match /Monthly Audit Report/, mail.subject
    assert_match /All Systems/, mail.subject
    assert_match /Current State/, mail.subject
    assert_equal 1, mail.attachments.size
    xlsx = xlsx_attachment(mail)
    assert_match(/monthly_reports_all_systems_#{Date.current.strftime('%Y%m%d')}\.xlsx/, xlsx.filename)
    assert_equal 'PK', xlsx.body.decoded[0, 2]
  end

  def test_all_systems_monthly_report_monthly_mode
    reports_by_system = {
      'SFS' => [
        { user_id: '333', user_name: 'Carol', user_type: 'Employee', user_uid: 'carol', status: 'active', account_action: 'Add', closed_on: Date.parse('2026-01-10'), request_code: 'SAA',
issue_id: 30 }
      ]
    }
    mode = 'monthly'
    selected_month_num = 1
    selected_year = 2026
    as_of_time = Date.new(2026, 1, 1).beginning_of_month.in_time_zone

    mail = AuditReportsMailer.all_systems_monthly_report(
      'user@example.com',
      reports_by_system,
      mode,
      as_of_time,
      selected_month_num,
      selected_year
    )

    assert_match /January 2026/, mail.subject
    assert_match /All Systems/, mail.subject
    assert_equal 1, mail.attachments.size
    assert_match /monthly_reports_all_systems_202601\.xlsx/, xlsx_attachment(mail).filename
  end

  def test_all_systems_monthly_report_multiple_recipients
    reports_by_system = { 'AIX' => [] }
    mode = 'current'
    as_of_time = Time.current

    recipients = ['user1@example.com', 'user2@example.com']
    mail = AuditReportsMailer.all_systems_monthly_report(recipients, reports_by_system, mode, as_of_time)

    assert_equal recipients, mail.to
  end
end
