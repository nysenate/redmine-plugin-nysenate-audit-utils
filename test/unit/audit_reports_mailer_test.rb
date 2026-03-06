# frozen_string_literal: true

require_relative '../test_helper'

class AuditReportsMailerTest < ActiveSupport::TestCase
  include Redmine::I18n

  def setup
    ActionMailer::Base.deliveries.clear
    Setting.plain_text_mail = '0'
    Setting.default_language = 'en'
  end

  def test_daily_report_generates_email
    report_data = [
      {
        employee_name: 'John Doe',
        account_statuses: [{ request_code: 'OAA' }],
        open_requests: [],
        transaction_codes: 'APP',
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
    assert_match /daily_report.*\.csv/, mail.attachments.first.filename
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

  def test_daily_report_csv_attachment_content
    report_data = [
      {
        subject_name: 'Jane Smith',
        account_statuses: [{ request_code: 'OAA' }],
        open_requests: [{ request_code: 'OAU' }],
        transaction_codes: 'TRN',
        phone_number: '555-5678',
        office: 'Personnel',
        office_location: 'NYC',
        subject_id: '67890',
        post_date: Date.parse('2026-03-01')
      }
    ]
    from_date = Time.zone.parse('2026-03-01 00:00:00')
    to_date = Time.zone.parse('2026-03-01 23:59:59')

    mail = AuditReportsMailer.daily_report('user@example.com', report_data, from_date, to_date)

    csv_content = mail.attachments.first.body.to_s
    assert_match /Subject Name/, csv_content
    assert_match /Jane Smith/, csv_content
    assert_match /67890/, csv_content
  end

  def test_weekly_report_generates_email
    report_data = [
      {
        issue_id: 1,
        subject: 'Test Issue',
        status: 'Open',
        employee_id: '12345',
        employee_uid: 'jdoe',
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
    assert_match /weekly_report.*\.csv/, mail.attachments.first.filename
    # Check HTML part for content
    assert_match /Active Tickets/, mail.html_part.body.to_s
    assert_match /1/, mail.html_part.body.to_s
  end

  def test_weekly_report_csv_attachment_content
    report_data = [
      {
        issue_id: 42,
        subject: 'Account Request',
        status: 'Closed',
        subject_id: '11111',
        subject_uid: 'test_user',
        request_code: 'OAD',
        updated_on: Time.zone.parse('2026-03-01 15:30:00'),
        created_on: Time.zone.parse('2026-03-01 10:00:00')
      }
    ]
    from_date = Date.parse('2026-03-01')
    to_date = Time.zone.parse('2026-03-07 23:59:59')

    mail = AuditReportsMailer.weekly_report('user@example.com', report_data, from_date, to_date)

    csv_content = mail.attachments.first.body.to_s
    assert_match /Subject UID/, csv_content
    assert_match /test_user/, csv_content
    assert_match /11111/, csv_content
    assert_match /Account Request/, csv_content
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
    assert_match /monthly_report_oracle-sfms_current\.csv/, mail.attachments.first.filename
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
    assert_match /monthly_report_aix_202601\.csv/, mail.attachments.first.filename
    # Check HTML part for content
    assert_match /Historical Snapshot/, mail.html_part.body.to_s
    assert_match /January 2026/, mail.html_part.body.to_s
  end

  def test_monthly_report_csv_attachment_content
    report_data = [
      {
        subject_id: '99999',
        subject_name: 'Test User',
        subject_type: 'Employee',
        subject_uid: 'testuser',
        account_type: 'SFS',
        status: 'active',
        account_action: 'Update',
        closed_on: Date.parse('2026-02-10'),
        request_code: 'SAU',
        issue_id: 200
      }
    ]
    target_system = 'SFS'
    mode = 'current'
    as_of_time = Time.current

    mail = AuditReportsMailer.monthly_report(
      'user@example.com',
      report_data,
      target_system,
      mode,
      as_of_time
    )

    csv_content = mail.attachments.first.body.to_s
    assert_match /Subject Name/, csv_content
    assert_match /Test User/, csv_content
    assert_match /99999/, csv_content
    assert_match /testuser/, csv_content
  end

end
