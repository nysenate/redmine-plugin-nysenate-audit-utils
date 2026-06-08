# frozen_string_literal: true

namespace :nysenate_audit_utils do
  # Archive a generated report to the project's Files repository.
  # Prints operator-visible status to stdout; ProjectFileArchiver handles logging.
  def archive_report_to_project_files(project:, filename:, content:, content_type:, description: nil)
    unless project.module_enabled?(:files)
      puts "Skipped archiving to project Files (Files module not enabled on '#{project.identifier}')"
      return
    end

    if NysenateAuditUtils::Reporting::ProjectFileArchiver.archive(
      project: project,
      filename: filename,
      content: content,
      content_type: content_type,
      description: description
    )
      puts "Archived report to project Files: #{filename}"
    else
      puts "Warning: failed to archive report to project Files (see log)"
    end
  end

  desc <<-END_DESC
Send daily audit report via email.

Available options:
  * project_id => project identifier (required)
  * recipients => comma-separated list of email addresses (optional, uses plugin settings if not provided)
  * mode       => 'business_day' (default) or 'range'
                  - business_day: single-day mode. Uses end_date (default: today); range = previous
                    business day 00:00 → end_date 00:00. If end_date is a Monday, range starts at
                    the previous Friday 00:00. start_date is ignored in this mode.
                  - range: uses start_date and end_date explicitly.
  * start_date => start date in YYYY-MM-DD format (range mode only, defaults to yesterday)
  * end_date   => end date in YYYY-MM-DD format (defaults to today; range ends at 00:00 server local time, exclusive)

Example:
  rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" RAILS_ENV="production"  # business_day mode, today
  rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" mode="business_day" end_date="2026-05-18" RAILS_ENV="production"
  rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" mode="range" start_date="2026-05-15" end_date="2026-05-17" RAILS_ENV="production"
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

    # Determine mode (default: business_day)
    mode = ENV['mode'].presence == 'range' ? 'range' : 'business_day'

    # Parse optional date parameters (system local time, midnight)
    if mode == 'business_day'
      selected_date = ENV['end_date'].presence ? Date.parse(ENV['end_date']) : Date.current
      from_date, to_date = NysenateAuditUtils::Reporting::DailyReportService.business_day_range(selected_date)
    else
      from_date = if ENV['start_date'].presence
                    Date.parse(ENV['start_date']).to_time
                  else
                    Date.yesterday.to_time
                  end

      to_date = if ENV['end_date'].presence
                  Date.parse(ENV['end_date']).to_time
                else
                  Date.current.to_time
                end
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
        service.to_date,
        project.identifier
      )
    end

    # Archive CSV to project Files
    archive_report_to_project_files(
      project: project,
      filename: "daily_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
      content: NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(
        report_data, from_date: service.from_date, to_date: service.to_date
      ),
      content_type: 'text/csv',
      description: "Daily audit report #{service.from_date.strftime('%Y-%m-%d')} to #{service.to_date.strftime('%Y-%m-%d')}"
    )

    puts "Daily report sent to: #{recipient_list.join(', ')}"
    puts "Mode: #{mode}"
    puts "Report period: #{service.from_date.strftime('%Y-%m-%d %H:%M')} to #{service.to_date.strftime('%Y-%m-%d %H:%M')}"
    puts "Employees with status changes: #{report_data.size}"
  end

  desc <<-END_DESC
Send weekly audit report via email. Reports only closed tickets.

Available options:
  * project_id => project identifier (required)
  * recipients => comma-separated list of email addresses (optional, uses plugin settings if not provided)
  * start_date => report start date YYYY-MM-DD (optional, defaults to previous Sunday)
  * end_date   => report end date YYYY-MM-DD (optional, defaults to most recent Sunday)

Example:
  rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" RAILS_ENV="production"
  rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" start_date="2026-03-29" end_date="2026-04-05" RAILS_ENV="production"
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

    # Parse optional date range (system local time)
    from_date = ENV['start_date'].present? ? Date.parse(ENV['start_date']).to_time : nil
    to_date = ENV['end_date'].present? ? Date.parse(ENV['end_date']).to_time.end_of_day : nil

    # Generate report
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: project,
      from_date: from_date,
      to_date: to_date
    )
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
        service.to_date,
        project.identifier
      )
    end

    # Archive CSV to project Files
    archive_report_to_project_files(
      project: project,
      filename: "weekly_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
      content: NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv(
        report_data, from_date: service.from_date, to_date: service.to_date
      ),
      content_type: 'text/csv',
      description: "Weekly audit report #{service.from_date.strftime('%Y-%m-%d')} to #{service.to_date.strftime('%Y-%m-%d')}"
    )

    puts "Weekly report sent to: #{recipient_list.join(', ')}"
    puts "Report period: #{service.from_date.strftime('%Y-%m-%d')} to #{service.to_date.strftime('%Y-%m-%d')}"
    puts "Closed tickets: #{report_data.size}"
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
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.to_time
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
        selected_year,
        project.identifier,
        status_filter
      )
    end

    # Archive CSV to project Files
    filename_suffix = mode == 'current' ? 'current' : "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
    archive_report_to_project_files(
      project: project,
      filename: "monthly_report_#{target_system.parameterize}_#{filename_suffix}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
      content: NysenateAuditUtils::Reporting::CsvGenerator.generate_monthly_csv(
        report_data, as_of_time: as_of_time, target_system: target_system
      ),
      content_type: 'text/csv',
      description: "Monthly audit report - #{target_system} - #{filename_suffix}"
    )

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
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.to_time
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
        selected_year,
        project.identifier,
        status_filter
      )
    end

    # Archive ZIP to project Files
    filename_suffix = mode == 'current' ? 'current' : "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
    archive_report_to_project_files(
      project: project,
      filename: "monthly_reports_all_systems_#{filename_suffix}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip",
      content: NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(
        reports_by_system, filename_suffix, as_of_time: as_of_time
      ),
      content_type: 'application/zip',
      description: "Monthly audit report - All Systems - #{filename_suffix}"
    )

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
