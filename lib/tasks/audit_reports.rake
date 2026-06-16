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

  # Parse a truthy flag from an ENV value ('1', 'true', or 'yes').
  def truthy_env?(value)
    %w[1 true yes].include?(value.to_s.downcase)
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
  * no_email   => '1', 'true', or 'yes' to skip sending the email (the CSV is still
                  archived to project Files); recipients are not required in this mode

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

    no_email = truthy_env?(ENV['no_email'])

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    if !no_email && recipients.blank?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_daily_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.to_s.split(',').map(&:strip)

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

    # Send email with CSV attachment (unless suppressed)
    unless no_email
      Mailer.with_synched_deliveries do
        AuditReportsMailer.deliver_daily_report(
          recipient_list,
          report_data,
          service.from_date,
          service.to_date,
          project.identifier
        )
      end
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

    if no_email
      puts "Daily report email skipped (no_email set)"
    else
      puts "Daily report sent to: #{recipient_list.join(', ')}"
    end
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
  * no_email   => '1', 'true', or 'yes' to skip sending the email (the CSV is still
                  archived to project Files); recipients are not required in this mode

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

    no_email = truthy_env?(ENV['no_email'])

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    if !no_email && recipients.blank?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_weekly_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.to_s.split(',').map(&:strip)

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

    # Send email with CSV attachment (unless suppressed)
    unless no_email
      Mailer.with_synched_deliveries do
        AuditReportsMailer.deliver_weekly_report(
          recipient_list,
          report_data,
          service.from_date,
          service.to_date,
          project.identifier
        )
      end
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

    if no_email
      puts "Weekly report email skipped (no_email set)"
    else
      puts "Weekly report sent to: #{recipient_list.join(', ')}"
    end
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
  * no_email       => '1', 'true', or 'yes' to skip sending the email (the CSV is still
                      archived to project Files); recipients are not required in this mode

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

    no_email = truthy_env?(ENV['no_email'])

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    if !no_email && recipients.blank?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_monthly_report project_id=\"#{project_id}\" target_system=\"System\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.to_s.split(',').map(&:strip)

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

    # Send email with CSV attachment (unless suppressed)
    unless no_email
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

    if no_email
      puts "Monthly report email skipped (no_email set)"
    else
      puts "Monthly report sent to: #{recipient_list.join(', ')}"
    end
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

    no_email = truthy_env?(ENV['no_email'])

    # Parse recipients - use configured default if not provided
    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']

    if !no_email && recipients.blank?
      puts "Error: No recipients configured"
      puts "Either provide recipients parameter or configure default recipients in plugin settings"
      puts "Usage: rake nysenate_audit_utils:send_all_systems_monthly_report project_id=\"#{project_id}\" recipients=\"email1,email2\" RAILS_ENV=production"
      exit 1
    end

    recipient_list = recipients.to_s.split(',').map(&:strip)

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

    # Send email with ZIP attachment (unless suppressed)
    unless no_email
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
    if no_email
      puts "All-systems monthly report email skipped (no_email set)"
    else
      puts "All-systems monthly report sent to: #{recipient_list.join(', ')}"
    end
    puts "Systems included: #{reports_by_system.keys.join(', ')}"
    puts "Mode: #{mode}"
    if mode == 'current'
      puts "As of: #{as_of_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    else
      puts "Snapshot: #{Date::MONTHNAMES[selected_month_num]} #{selected_year}"
    end
    puts "Total accounts across all systems: #{total}"
  end

  desc <<-END_DESC
Audit and reconcile Account Holder info on tickets.

For each distinct (Account Holder Type, Account Holder ID) pair appearing on
issues in the given project, re-fetch authoritative data (ESS API for
Employees, tracked_users table for Vendor/Volunteer) and update any drifted
Account Holder custom fields (Name, Email, Phone, Status, UID, Office).

Produces a CSV report and emails it to the
configured recipients, and archives it to the project's Files repository.

Available options:
  * project_id => project identifier (required)
  * recipients => comma-separated email addresses (optional, uses plugin
                  settings if not provided)
  * dry_run    => '1', 'true', or 'yes' to skip writes and only report drift
  * force_email => '1', 'true', or 'yes' to always send the email even when
                  there are no changes or unresolved tickets
  * no_email   => '1', 'true', or 'yes' to never send the email (the CSV is still
                  archived to project Files); takes precedence over force_email and
                  recipients are not required in this mode

By default no email is sent when the audit finds no changes and no unresolved
tickets (the CSV is still archived to project Files); this applies to dry runs
too. Use force_email=1 to always send the email, or no_email=1 to never send it.

Example:
  rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" RAILS_ENV=production
  rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" dry_run=1 RAILS_ENV=production
  rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" force_email=1 RAILS_ENV=production
END_DESC

  task audit_account_holder_info: :environment do
    project_id = ENV['project_id'].presence
    unless project_id
      puts 'Error: project_id parameter is required'
      puts 'Usage: rake nysenate_audit_utils:audit_account_holder_info project_id="project_identifier" RAILS_ENV=production'
      exit 1
    end

    project = Project.find_by(identifier: project_id) || Project.find_by(id: project_id)
    unless project
      puts "Error: Project not found with identifier or id: #{project_id}"
      exit 1
    end

    no_email = truthy_env?(ENV['no_email'])

    recipients = ENV['recipients'].presence || Setting.plugin_nysenate_audit_utils['report_recipients']
    if !no_email && recipients.blank?
      puts 'Error: No recipients configured'
      puts 'Either provide recipients parameter or configure default recipients in plugin settings'
      exit 1
    end
    recipient_list = recipients.to_s.split(',').map(&:strip)

    dry_run = truthy_env?(ENV['dry_run'])
    force_email = truthy_env?(ENV['force_email'])

    service = NysenateAuditUtils::Reporting::UserInfoAuditService.new(
      project: project,
      dry_run: dry_run
    )
    result = service.run

    unless result.success?
      puts "Error running Account Holder info audit: #{result.errors.join('; ')}"
      exit 1
    end

    csv_data = NysenateAuditUtils::Reporting::UserInfoAuditCsvGenerator.generate(
      result, project: project, dry_run: dry_run
    )

    # Decide whether to email. By default, skip the email when the audit found
    # nothing actionable (no changes and no exceptions); force_email overrides
    # the skip. no_email suppresses the email unconditionally and takes
    # precedence over force_email. This applies to dry runs too.
    has_findings = result.changes.any? || result.exceptions.any?
    should_email = !no_email && (force_email || has_findings)

    email_error = nil
    if should_email
      begin
        Mailer.with_synched_deliveries do
          AuditReportsMailer.deliver_user_info_audit_report(
            recipient_list, result.summary, csv_data, project.identifier, dry_run
          )
        end
      rescue StandardError => e
        email_error = "#{e.class}: #{e.message}"
        Rails.logger.error(
          "[nysenate_audit_utils] Account Holder audit email delivery failed: #{email_error}\n" \
          "#{e.backtrace&.first(10)&.join("\n")}"
        )
        puts "Warning: failed to send Account Holder audit email: #{email_error}"
        puts 'Continuing to archive CSV so the run is not lost.'
      end
    end

    filename_stem = dry_run ? 'account_holder_audit_dryrun' : 'account_holder_audit'
    archive_report_to_project_files(
      project: project,
      filename: "#{filename_stem}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
      content: csv_data,
      content_type: 'text/csv',
      description: "Account Holder info audit#{dry_run ? ' (dry run)' : ''} for project #{project.identifier}"
    )

    summary = result.summary
    if email_error
      puts "Account Holder info audit NOT emailed (#{email_error})"
    elsif no_email
      puts 'Account Holder info audit email skipped (no_email set)'
    elsif !should_email
      puts 'Account Holder info audit email skipped (no changes or exceptions; use force_email=1 to override)'
    else
      puts "Account Holder info audit sent to: #{recipient_list.join(', ')}"
    end
    unresolved = summary[:unresolved_tickets].to_i
    puts "Mode: #{dry_run ? 'dry run (no changes applied)' : 'apply'}"
    puts "Total Tickets Scanned: #{summary[:tickets_scanned]}"
    puts "Unresolved tickets#{unresolved.positive? ? ' (review needed)' : ''}: #{unresolved}"
    puts "Total Account Holders checked: #{summary[:account_holders_checked]}"
    puts "Account Holders with changes: #{summary[:pairs_with_changes]}"
    puts "Field updates#{dry_run ? ' (would apply)' : ' applied'}: #{summary[:field_updates]}"
    puts "#{dry_run ? 'Tickets to update' : 'Tickets updated'}: #{summary[:tickets_updated]}"
    if summary[:unresolved_by_category].present?
      puts 'Unresolved Tickets by category:'
      summary[:unresolved_by_category].each { |cat, n| puts "  #{cat}: #{n}" }
    end
  end
end
