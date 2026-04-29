require 'csv'

class AuditReportsController < ApplicationController
  before_action :find_project
  before_action :authorize

  helper :sort
  include SortHelper

  def index
    # Report selection/navigation page
  end

  def daily
    from_date = parse_date_param(params[:start_date]) || Date.yesterday.to_time
    to_date   = parse_date_param(params[:end_date])   || Date.current.to_time

    validate_date_range!(from_date, to_date)

    service = NysenateAuditUtils::Reporting::DailyReportService.new(
      from_date: from_date,
      to_date: to_date,
      project: @project
    )

    @report_data = service.generate
    @from_date = service.from_date
    @to_date = service.to_date

    # Check if there were errors during report generation
    unless service.success?
      @error_message = service.errors.join('; ')
      render :error
      return
    end

    # Set up sorting
    sort_init 'post_date', 'asc'
    sort_update({
      'employee_name' => 'employee_name',
      'transaction_codes' => 'transaction_codes',
      'office' => 'office',
      'office_location' => 'office_location',
      'employee_id' => 'employee_id',
      'post_date' => 'post_date'
    })

    # Apply sorting to report data
    if @report_data.present?
      @report_data = sort_report_data(@report_data)
    end

    respond_to do |format|
      format.html
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data csv_data,
                  filename: "daily_report_#{Date.today.strftime('%Y%m%d')}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  rescue ArgumentError => e
    # Handle validation errors
    flash.now[:error] = e.message
    @from_date = Date.yesterday.to_time
    @to_date = Date.current.to_time
    @report_data = []
    render :daily
  rescue => e
    Rails.logger.error "Daily report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
    render :error
  end

  def weekly
    from_date = parse_date_param(params[:start_date])
    to_date = parse_date_param(params[:end_date])
    to_date = to_date.end_of_day if to_date && params[:end_date].present?

    service = NysenateAuditUtils::Reporting::WeeklyReportService.new(
      project: @project,
      from_date: from_date,
      to_date: to_date
    )
    @report_data = service.generate
    @from_date = service.from_date
    @to_date = service.to_date

    # Check if there were errors during report generation
    unless service.success?
      @error_message = service.errors.join('; ')
      render :error
      return
    end

    # Set up sorting
    sort_init 'updated_on', 'desc'
    sort_update({
      'issue_id' => 'issue_id',
      'subject' => 'subject',
      'status' => 'status',
      'user_id' => 'user_id',
      'user_uid' => 'user_uid',
      'user_name' => 'user_name',
      'office' => 'office',
      'request_code' => 'request_code',
      'updated_on' => 'updated_on',
      'created_on' => 'created_on',
      'closed_on' => 'closed_on'
    })

    # Apply sorting to report data
    @report_data = sort_report_data(@report_data) if @report_data.present?

    respond_to do |format|
      format.html
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data csv_data,
                  type: 'text/csv; header=present',
                  filename: "weekly_report_#{Date.current.strftime('%Y%m%d')}.csv"
      end
    end
  rescue => e
    Rails.logger.error "Weekly report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
    render :error
  end

  def monthly
    # Get valid target systems from custom field configuration
    target_system_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field
    @target_systems = target_system_field&.possible_values || ['Oracle / SFMS']

    # Calculate earliest closed issue date in the project
    earliest_closed_date = calculate_earliest_closed_date(@project)
    current_date = Date.current

    # Set earliest year/month (floor is the minimum of earliest closed date and current date)
    if earliest_closed_date && earliest_closed_date < current_date
      @earliest_year = earliest_closed_date.year
      @earliest_month = earliest_closed_date.month
    else
      @earliest_year = current_date.year
      @earliest_month = current_date.month
    end

    # Parse target_system parameter (use first valid system as default)
    target_system = params[:target_system].presence || @target_systems.first

    # Parse status_filter parameter (default to 'active')
    status_filter = params[:status_filter].presence || 'active'

    # Parse mode parameter (default to 'monthly')
    mode = params[:mode].presence || 'monthly'

    # Parse month/year and determine as_of_time based on mode
    if mode == 'current'
      # Current mode: show latest state (no time filtering)
      as_of_time = Time.current
      selected_month_num = nil
      selected_year = nil
    else
      # Monthly mode: show snapshot at beginning of selected month
      selected_month_num = (params[:month].presence || Date.current.month).to_i
      selected_year = (params[:year].presence || Date.current.year).to_i
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.to_time
    end

    # Generate report
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: target_system,
      as_of_time: as_of_time,
      status_filter: status_filter,
      project: @project
    )
    @report_data = service.generate
    @target_system = target_system
    @status_filter = status_filter
    @mode = mode
    @selected_month_num = selected_month_num
    @selected_year = selected_year
    @as_of_time = as_of_time

    # Handle errors
    unless service.success?
      @error_message = service.errors.join('; ')
      render :error
      return
    end

    # Set up sorting
    sort_init 'employee_id', 'asc'
    sort_update({
      'employee_id' => 'employee_id',
      'employee_name' => 'employee_name',
      'employee_uid' => 'employee_uid',
      'status' => 'status',
      'account_action' => 'account_action',
      'closed_on' => 'closed_on',
      'issue_id' => 'issue_id'
    })

    # Apply sorting
    if @report_data.present?
      @report_data = sort_report_data(@report_data)
    end

    # Respond to formats
    respond_to do |format|
      format.html
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_monthly_csv(
          @report_data, as_of_time: @as_of_time, target_system: target_system
        )
        filename_suffix = if mode == 'current'
                            'current'
                          else
                            "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
                          end
        send_data csv_data,
                  filename: "monthly_report_#{target_system.parameterize}_#{filename_suffix}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  rescue => e
    Rails.logger.error "Monthly report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
    render :error
  end

  def monthly_zip
    target_system_field = NysenateAuditUtils::CustomFieldConfiguration.target_system_field
    target_systems = target_system_field&.possible_values || ['Oracle / SFMS']

    mode = params[:mode].presence || 'monthly'
    status_filter = params[:status_filter].presence || 'all'

    if mode == 'current'
      as_of_time = Time.current
      filename_suffix = 'current'
    else
      selected_month_num = (params[:month].presence || Date.current.month).to_i
      selected_year = (params[:year].presence || Date.current.year).to_i
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.to_time
      filename_suffix = "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
    end

    reports_by_system = {}
    target_systems.each do |system|
      service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
        target_system: system,
        as_of_time: as_of_time,
        status_filter: status_filter,
        project: @project
      )
      data = service.generate
      if service.success?
        reports_by_system[system] = data
      else
        Rails.logger.warn "monthly_zip: skipping #{system} — #{service.errors.join('; ')}"
      end
    end

    zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(
      reports_by_system, filename_suffix, as_of_time: as_of_time
    )
    send_data zip_data,
              filename: "monthly_reports_all_systems_#{filename_suffix}.zip",
              type: 'application/zip',
              disposition: 'attachment'
  rescue => e
    Rails.logger.error "Monthly ZIP export failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate ZIP export: #{e.message}"
    render :error
  end

  private

  def parse_date_param(date_string)
    return nil if date_string.blank?

    Date.parse(date_string).to_time
  rescue ArgumentError => e
    Rails.logger.error "Failed to parse date parameter '#{date_string}': #{e.message}"
    nil
  end

  def validate_date_range!(from_date, to_date)
    # Ensure from_date is before to_date
    if from_date > to_date
      raise ArgumentError, "Start date must be before end date"
    end

    # Calculate the earliest allowed date (7 days ago from today)
    today = Date.current
    tomorrow = today + 1.day
    earliest_allowed = today - 7.days

    # Check if start date is before the earliest allowed date
    if from_date.to_date < earliest_allowed
      raise ArgumentError, "Start date cannot be more than 7 days in the past"
    end

    # Allow dates up to tomorrow
    if from_date.to_date > tomorrow
      raise ArgumentError, "Start date cannot be more than 1 day in the future"
    end
    if to_date.to_date > tomorrow
      raise ArgumentError, "End date cannot be more than 1 day in the future"
    end

    true
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def calculate_earliest_closed_date(project)
    # Get the user_id field ID
    user_id_field_id = NysenateAuditUtils::CustomFieldConfiguration.user_id_field_id
    return nil unless user_id_field_id

    # Find the earliest closed issue in the project that has the user_id custom field
    Issue
      .where(project_id: project.id)
      .joins(:status)
      .joins(:custom_values)
      .where(issue_statuses: { is_closed: true })
      .where.not(closed_on: nil)
      .where(custom_values: { custom_field_id: user_id_field_id })
      .minimum(:closed_on)
      &.to_date
  end

  def sort_report_data(data)
    return data unless @sort_criteria

    sort_key = @sort_criteria.first_key
    sort_order = @sort_criteria.first_asc? ? 1 : -1

    data.sort do |a, b|
      a_val = a[sort_key.to_sym]
      b_val = b[sort_key.to_sym]

      # Handle nil values - push them to the end
      if a_val.nil? && b_val.nil?
        0
      elsif a_val.nil?
        1
      elsif b_val.nil?
        -1
      else
        (a_val <=> b_val) * sort_order
      end
    end
  end
end