# frozen_string_literal: true

namespace :nysenate_audit_utils do
  desc <<-END_DESC
Send daily audit report via email.

Available options:
  * project_id => project identifier (required)
  * recipients => comma-separated list of email addresses (optional, uses plugin settings if not provided)
  * start_date => start date in YYYY-MM-DD format (optional, defaults to business day calculation)
  * end_date   => end date in YYYY-MM-DD format (optional, defaults to now)

Example:
  rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" recipients="user@example.com,admin@example.com" RAILS_ENV="production"
  rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" RAILS_ENV="production"  # Uses configured recipients
END_DESC

  task send_daily_report: :environment do
    # Parse project_id - required
    project_id = ENV['project_id'].presence
    unless project_id
      puts "Error: project_id parameter is required"
      puts "Usage: rake nysenate_audit_utils:send_daily_report project_id=\"project_identifier\" RAILS_ENV=production"
      exit 1
    end

    # Find project
    project = Project.find_by(identifier: project_id) || Project.find_by(id: project_id)
    unless project
      puts "Error: Project not found with identifier or id: #{project_id}"
      exit 1
    end

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    unless recipients.present?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_daily_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.split(',').map(&:strip)

    # Parse optional date parameters
    from_date = if ENV['start_date'].presence
                  Date.parse(ENV['start_date']).in_time_zone.beginning_of_day
                else
                  nil  # Let service use default business day calculation
                end

    to_date = if ENV['end_date'].presence
                Date.parse(ENV['end_date']).in_time_zone.end_of_day
              else
                nil  # Let service use default (now)
              end

    # Generate report
    service = NysenateAuditUtils::Reporting::DailyReportService.new(
      from_date: from_date,
      to_date: to_date,
      project: project
    )
    report_data = service.generate

    unless service.success?
      puts "Error generating daily report: #{service.errors.join('; ')}"
      exit 1
    end

    # Send email with CSV attachment
    Mailer.with_synched_deliveries do
      AuditReportsMailer.deliver_daily_report(
        recipient_list,
        report_data,
        service.from_date,
        service.to_date
      )
    end

    puts "Daily report sent to: #{recipient_list.join(', ')}"
    puts "Report period: #{service.from_date.strftime('%Y-%m-%d %H:%M')} to #{service.to_date.strftime('%Y-%m-%d %H:%M')}"
    puts "Employees with status changes: #{report_data.size}"
  end

  desc <<-END_DESC
Send weekly audit report via email.

Available options:
  * project_id => project identifier (required)
  * recipients => comma-separated list of email addresses (optional, uses plugin settings if not provided)

Example:
  rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" recipients="user@example.com,admin@example.com" RAILS_ENV="production"
  rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" RAILS_ENV="production"  # Uses configured recipients
END_DESC

  task send_weekly_report: :environment do
    # Parse project_id - required
    project_id = ENV['project_id'].presence
    unless project_id
      puts "Error: project_id parameter is required"
      puts "Usage: rake nysenate_audit_utils:send_weekly_report project_id=\"project_identifier\" RAILS_ENV=production"
      exit 1
    end

    # Find project
    project = Project.find_by(identifier: project_id) || Project.find_by(id: project_id)
    unless project
      puts "Error: Project not found with identifier or id: #{project_id}"
      exit 1
    end

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    unless recipients.present?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_weekly_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.split(',').map(&:strip)

    # Generate report
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(project: project)
    report_data = service.generate

    unless service.success?
      puts "Error generating weekly report: #{service.errors.join('; ')}"
      exit 1
    end

    # Send email with CSV attachment
    Mailer.with_synched_deliveries do
      AuditReportsMailer.deliver_weekly_report(
        recipient_list,
        report_data,
        service.from_date,
        service.to_date
      )
    end

    puts "Weekly report sent to: #{recipient_list.join(', ')}"
    puts "Report period: Week of #{service.from_date.strftime('%Y-%m-%d')}"
    puts "Active tickets: #{report_data.size}"
  end

  desc <<-END_DESC
Send monthly audit report via email.

Available options:
  * project_id     => project identifier (required)
  * target_system  => target system name (required)
  * recipients     => comma-separated list of email addresses (optional, uses plugin settings if not provided)
  * mode           => report mode: "current" or "monthly" (default: "current")
  * month          => month number 1-12 (for monthly mode, default: current month)
  * year           => year (for monthly mode, default: current year)

Example:
  rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="AIX" RAILS_ENV="production"
  rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="AIX" mode=current RAILS_ENV="production"
  rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="SFS" mode=monthly month=1 year=2026 RAILS_ENV="production"
  rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="AIX" recipients="user@example.com" RAILS_ENV="production"
END_DESC

  task send_monthly_report: :environment do
    # Parse project_id - required
    project_id = ENV['project_id'].presence
    unless project_id
      puts "Error: project_id parameter is required"
      puts "Usage: rake nysenate_audit_utils:send_monthly_report project_id=\"project_identifier\" target_system=\"System\" RAILS_ENV=production"
      exit 1
    end

    # Find project
    project = Project.find_by(identifier: project_id) || Project.find_by(id: project_id)
    unless project
      puts "Error: Project not found with identifier or id: #{project_id}"
      exit 1
    end

    # Parse target_system - required
    target_system = ENV['target_system'].presence
    unless target_system
      puts "Error: target_system parameter is required"
      puts "Usage: rake nysenate_audit_utils:send_monthly_report project_id=\"#{project_id}\" target_system=\"System\" RAILS_ENV=production"
      exit 1
    end

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    unless recipients.present?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_monthly_report project_id=\"#{project_id}\" target_system=\"System\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.split(',').map(&:strip)

    # Parse optional parameters
    mode = ENV['mode'].presence || 'monthly'
    status_filter = ENV['status_filter'].presence || 'active'

    # Determine as_of_time based on mode
    if mode == 'current'
      as_of_time = Time.current
      selected_month_num = nil
      selected_year = nil
    else
      selected_month_num = (ENV['month'].presence || Date.current.month).to_i
      selected_year = (ENV['year'].presence || Date.current.year).to_i
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.in_time_zone
    end

    # Generate report
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: target_system,
      as_of_time: as_of_time,
      status_filter: status_filter,
      project: project
    )
    report_data = service.generate

    unless service.success?
      puts "Error generating monthly report: #{service.errors.join('; ')}"
      exit 1
    end

    # Send email with CSV attachment
    Mailer.with_synched_deliveries do
      AuditReportsMailer.deliver_monthly_report(
        recipient_list,
        report_data,
        target_system,
        mode,
        as_of_time,
        selected_month_num,
        selected_year
      )
    end

    puts "Monthly report sent to: #{recipient_list.join(', ')}"
    puts "Target system: #{target_system}"
    puts "Mode: #{mode}"
    if mode == 'current'
      puts "As of: #{as_of_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    else
      puts "Snapshot: #{Date::MONTHNAMES[selected_month_num]} #{selected_year}"
    end
    puts "Total accounts: #{report_data.size}"
  end

  desc "Send monthly audit report for ALL target systems as a ZIP email attachment"
  task send_all_systems_monthly_report: :environment do
    # Parse project_id - required
    project_id = ENV['project_id'].presence
    unless project_id
      puts "Error: project_id parameter is required"
      puts "Usage: rake nysenate_audit_utils:send_all_systems_monthly_report project_id=\"project_identifier\" RAILS_ENV=production"
      exit 1
    end

    # Find project
    project = Project.find_by(identifier: project_id) || Project.find_by(id: project_id)
    unless project
      puts "Error: Project not found with identifier or id: #{project_id}"
      exit 1
    end

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    unless recipients.present?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_all_systems_monthly_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.split(',').map(&:strip)

    # Get all target systems from configuration
    target_system_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field
    target_systems = target_system_field&.possible_values || ['Oracle / SFMS']

    if target_systems.empty?
      puts "Error: No target systems configured"
      exit 1
    end

    # Parse optional parameters
    mode = ENV['mode'].presence || 'monthly'
    status_filter = ENV['status_filter'].presence || 'active'

    # Determine as_of_time based on mode
    if mode == 'current'
      as_of_time = Time.current
      selected_month_num = nil
      selected_year = nil
    else
      selected_month_num = (ENV['month'].presence || Date.current.month).to_i
      selected_year = (ENV['year'].presence || Date.current.year).to_i
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.in_time_zone
    end

    # Generate reports for each system
    reports_by_system = {}
    target_systems.each do |system|
      service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
        target_system: system,
        as_of_time: as_of_time,
        status_filter: status_filter,
        project: project
      )
      data = service.generate

      if service.success?
        reports_by_system[system] = data
        puts "  #{system}: #{data.size} accounts"
      else
        puts "  Warning: skipping #{system} — #{service.errors.join('; ')}"
      end
    end

    if reports_by_system.empty?
      puts "Error: No report data could be generated for any system"
      exit 1
    end

    # Send email with ZIP attachment
    Mailer.with_synched_deliveries do
      AuditReportsMailer.deliver_all_systems_monthly_report(
        recipient_list,
        reports_by_system,
        mode,
        as_of_time,
        selected_month_num,
        selected_year
      )
    end

    total = reports_by_system.values.sum(&:size)
    puts "All-systems monthly report sent to: #{recipient_list.join(', ')}"
    puts "Systems included: #{reports_by_system.keys.join(', ')}"
    puts "Mode: #{mode}"
    if mode == 'current'
      puts "As of: #{as_of_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    else
      puts "Snapshot: #{Date::MONTHNAMES[selected_month_num]} #{selected_year}"
    end
    puts "Total accounts across all systems: #{total}"
  end
end
