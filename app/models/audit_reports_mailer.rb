# frozen_string_literal: true

class AuditReportsMailer < ActionMailer::Base
  include Redmine::I18n
  layout 'mailer'

  def default_url_options
    ::Mailer.default_url_options
  end


  # Send daily report email with CSV attachment
  #
  # @param recipients [Array<String>, String] Email address(es) to send to
  # @param report_data [Array<Hash>] Daily report data
  # @param from_date [Time] Start date for the report
  # @param to_date [Time] End date for the report
  def daily_report(recipients, report_data, from_date, to_date, project_id = nil)
    @report_data = report_data
    @from_date = from_date
    @to_date = to_date
    @employee_count = report_data.size
    if project_id
      @report_url = daily_project_audit_reports_url(
        project_id,
        start_date: from_date.to_date.to_s,
        end_date: to_date.to_date.to_s
      )
    end

    # Generate and attach CSV
    csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(report_data)
    attachments["daily_report_#{Date.today.strftime('%Y%m%d')}.csv"] = csv_data

    mail(
      from: Setting.mail_from,
      to: recipients,
      subject: "Daily Audit Report - #{from_date.strftime('%Y-%m-%d')} to #{to_date.strftime('%Y-%m-%d')}"
    )
  end

  # Send weekly report email with CSV attachment
  #
  # @param recipients [Array<String>, String] Email address(es) to send to
  # @param report_data [Array<Hash>] Weekly report data
  # @param from_date [Date] Start date for the report (Monday)
  # @param to_date [Time] End date for the report (current time)
  def weekly_report(recipients, report_data, from_date, to_date, project_id = nil)
    @report_data = report_data
    @from_date = from_date
    @to_date = to_date
    @ticket_count = report_data.size
    @report_url = weekly_project_audit_reports_url(
      project_id,
      start_date: from_date.to_date.to_s,
      end_date: to_date.to_date.to_s
    ) if project_id

    # Generate and attach CSV
    csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv(report_data)
    attachments["weekly_report_#{Date.current.strftime('%Y%m%d')}.csv"] = csv_data

    mail(
      from: Setting.mail_from,
      to: recipients,
      subject: "Weekly Audit Report - Week of #{from_date.strftime('%Y-%m-%d')}"
    )
  end

  # Send monthly report email with CSV attachment
  #
  # @param recipients [Array<String>, String] Email address(es) to send to
  # @param report_data [Array<Hash>] Monthly report data
  # @param target_system [String] Target system name
  # @param mode [String] Report mode: 'current' or 'monthly'
  # @param as_of_time [Time] Time snapshot for the report
  # @param selected_month_num [Integer, nil] Month number (for monthly mode)
  # @param selected_year [Integer, nil] Year (for monthly mode)
  def monthly_report(recipients, report_data, target_system, mode, as_of_time, selected_month_num = nil, selected_year = nil, project_id = nil, status_filter = nil)
    @report_data = report_data
    @target_system = target_system
    @mode = mode
    @as_of_time = as_of_time
    @selected_month_num = selected_month_num
    @selected_year = selected_year
    @account_count = report_data.size
    if project_id
      url_params = { target_system: target_system, mode: mode }
      url_params[:status_filter] = status_filter if status_filter
      url_params.merge!(month: selected_month_num, year: selected_year) if mode != 'current'
      @report_url = monthly_project_audit_reports_url(project_id, url_params)
    end

    # Generate and attach CSV with appropriate filename
    csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_monthly_csv(report_data)
    filename_suffix = if mode == 'current'
                        'current'
                      else
                        "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
                      end
    attachments["monthly_report_#{target_system.parameterize}_#{filename_suffix}.csv"] = csv_data

    # Build subject line
    email_subject = if mode == 'current'
                "Monthly Audit Report - #{target_system} - Current State"
              else
                "Monthly Audit Report - #{target_system} - #{Date::MONTHNAMES[selected_month_num]} #{selected_year}"
              end

    mail(
      from: Setting.mail_from,
      to: recipients,
      subject: email_subject
    )
  end

  # Class method to deliver daily report
  #
  # @param recipients [Array<String>, String] Email address(es)
  # @param report_data [Array<Hash>] Report data
  # @param from_date [Time] Start date
  # @param to_date [Time] End date
  def self.deliver_daily_report(recipients, report_data, from_date, to_date, project_id = nil)
    daily_report(recipients, report_data, from_date, to_date, project_id).deliver_later
  end

  # Class method to deliver weekly report
  #
  # @param recipients [Array<String>, String] Email address(es)
  # @param report_data [Array<Hash>] Report data
  # @param from_date [Date] Start date
  # @param to_date [Time] End date
  def self.deliver_weekly_report(recipients, report_data, from_date, to_date, project_id = nil)
    weekly_report(recipients, report_data, from_date, to_date, project_id).deliver_later
  end

  # Class method to deliver monthly report
  #
  # @param recipients [Array<String>, String] Email address(es)
  # @param report_data [Array<Hash>] Report data
  # @param target_system [String] Target system
  # @param mode [String] Report mode
  # @param as_of_time [Time] Time snapshot
  # @param selected_month_num [Integer, nil] Month number
  # @param selected_year [Integer, nil] Year
  def self.deliver_monthly_report(recipients, report_data, target_system, mode, as_of_time, selected_month_num = nil, selected_year = nil, project_id = nil, status_filter = nil)
    monthly_report(recipients, report_data, target_system, mode, as_of_time, selected_month_num, selected_year, project_id, status_filter).deliver_later
  end

  # Send all-systems monthly report email with ZIP attachment
  #
  # @param recipients [Array<String>, String] Email address(es) to send to
  # @param reports_by_system [Hash<String, Array<Hash>>] Map of system name => report data
  # @param mode [String] Report mode: 'current' or 'monthly'
  # @param as_of_time [Time] Time snapshot for the report
  # @param selected_month_num [Integer, nil] Month number (for monthly mode)
  # @param selected_year [Integer, nil] Year (for monthly mode)
  def all_systems_monthly_report(recipients, reports_by_system, mode, as_of_time, selected_month_num = nil, selected_year = nil, project_id = nil, status_filter = nil)
    @reports_by_system = reports_by_system
    @mode = mode
    @as_of_time = as_of_time
    @selected_month_num = selected_month_num
    @selected_year = selected_year
    @system_counts = reports_by_system.transform_values(&:size)
    if project_id
      url_params = { mode: mode }
      url_params[:status_filter] = status_filter if status_filter
      url_params.merge!(month: selected_month_num, year: selected_year) if mode != 'current'
      @report_url = monthly_project_audit_reports_url(project_id, url_params)
    end

    filename_suffix = if mode == 'current'
                        'current'
                      else
                        "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
                      end

    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(reports_by_system, filename_suffix)
    attachments["monthly_reports_all_systems_#{filename_suffix}.zip"] = { mime_type: 'application/zip', content: zip_data }

    email_subject = if mode == 'current'
                      'Monthly Audit Report - All Systems - Current State'
                    else
                      "Monthly Audit Report - All Systems - #{Date::MONTHNAMES[selected_month_num]} #{selected_year}"
                    end

    mail(
      from: Setting.mail_from,
      to: recipients,
      subject: email_subject
    )
  end

  # Class method to deliver all-systems monthly report
  #
  # @param recipients [Array<String>, String] Email address(es)
  # @param reports_by_system [Hash<String, Array<Hash>>] Map of system name => report data
  # @param mode [String] Report mode
  # @param as_of_time [Time] Time snapshot
  # @param selected_month_num [Integer, nil] Month number
  # @param selected_year [Integer, nil] Year
  def self.deliver_all_systems_monthly_report(recipients, reports_by_system, mode, as_of_time, selected_month_num = nil, selected_year = nil, project_id = nil, status_filter = nil)
    all_systems_monthly_report(recipients, reports_by_system, mode, as_of_time, selected_month_num, selected_year, project_id, status_filter).deliver_later
  end
end
