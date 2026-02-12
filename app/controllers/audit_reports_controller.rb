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
    # Handle day mode vs range mode
    if params[:mode] == "day"
      # Day mode: use end_date parameter for the selected date
      selected_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
      if selected_date
        from_date = selected_date.beginning_of_day
        to_date = selected_date.end_of_day
      else
        from_date = nil
        to_date = nil
      end
    else
      # Range mode: parse date parameters from the date pickers
      from_date = parse_date_param(params[:start_date])
      to_date = parse_date_param(params[:end_date])
      to_date = to_date.end_of_day if to_date
    end

    # Validate date range (must be within 7 days)
    if from_date && to_date
      validate_date_range!(from_date, to_date)
    end

    service = NysenateAuditUtils::Reporting::DailyReportService.new(
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
        csv_data = generate_daily_csv(@report_data)
        send_data csv_data,
                  filename: "daily_report_#{Date.today.strftime('%Y%m%d')}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  rescue ArgumentError => e
    # Handle validation errors
    flash.now[:error] = e.message
    @from_date = Time.zone.now.beginning_of_day.yesterday
    @to_date = Time.zone.now
    @report_data = []
    render :daily
  rescue => e
    Rails.logger.error "Daily report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
    render :error
  end

  def weekly
    service = NysenateAuditUtils::Reporting::WeeklyReportService.new
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
      'employee_id' => 'employee_id',
      'employee_uid' => 'employee_uid',
      'request_code' => 'request_code',
      'updated_on' => 'updated_on'
    })

    # Apply sorting to report data
    if @report_data.present?
      @report_data = sort_report_data(@report_data)
    end

    respond_to do |format|
      format.html
      format.csv do
        csv_data = generate_weekly_csv(@report_data)
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
    # Parse target_system parameter
    target_system = params[:target_system].presence || 'Oracle / SFMS'

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
      as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.in_time_zone
    end

    # Generate report
    service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
      target_system: target_system,
      as_of_time: as_of_time
    )
    @report_data = service.generate
    @target_system = target_system
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
        csv_data = generate_monthly_csv(@report_data)
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

  private

  def parse_date_param(date_string)
    return nil if date_string.blank?

    # Parse date format: YYYY-MM-DD
    Date.parse(date_string).in_time_zone
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

  def generate_daily_csv(data)
    return '' unless data

    CSV.generate do |csv|
      # Header row
      csv << [
        'Employee Name',
        'Account Status',
        'Open Tickets',
        'Transaction Codes',
        'Phone Number',
        'Office',
        'Office Location',
        'Employee ID',
        'Post Date'
      ]

      # Data rows
      data.each do |row|
        # Format account statuses as comma-separated request codes
        account_status_str = if row[:account_statuses].present?
          row[:account_statuses].map { |s| s[:request_code] || s[:account_type] }.join(', ')
        else
          ''
        end

        # Format open requests as comma-separated request codes
        open_tickets_str = if row[:open_requests].present?
          row[:open_requests].map { |r| r[:request_code] || r[:account_type] }.join(', ')
        else
          ''
        end

        csv << [
          row[:employee_name],
          account_status_str,
          open_tickets_str,
          row[:transaction_codes],
          row[:phone_number],
          row[:office],
          row[:office_location],
          row[:employee_id],
          row[:post_date]
        ]
      end
    end
  end

  def generate_weekly_csv(data)
    return '' unless data

    CSV.generate do |csv|
      # Header row
      csv << [
        'Employee UID',
        'Employee Number',
        'Request Code',
        'Ticket Description',
        'Status',
        'Updated On'
      ]

      # Data rows
      data.each do |row|
        csv << [
          row[:employee_uid],
          row[:employee_id],
          row[:request_code],
          row[:subject],
          row[:status],
          row[:updated_on]&.strftime('%Y-%m-%d %H:%M')
        ]
      end
    end
  end

  def generate_monthly_csv(data)
    return '' unless data

    CSV.generate do |csv|
      # Header row (matches web view layout with request_code added)
      csv << [
        'Employee Name',
        'Employee ID',
        'Employee UID',
        'Account Status',
        'Last Updated',
        'Last Issue',
        'Last Action',
        'Request Code'
      ]

      # Data rows
      data.each do |row|
        csv << [
          row[:employee_name],
          row[:employee_id],
          row[:employee_uid],
          row[:status],
          row[:closed_on]&.strftime('%Y-%m-%d'),
          row[:issue_id],
          row[:account_action],
          row[:request_code]
        ]
      end
    end
  end
end