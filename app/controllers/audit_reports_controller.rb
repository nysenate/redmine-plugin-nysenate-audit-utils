require 'csv'

class AuditReportsController < ApplicationController
  before_action :find_project
  before_action :authorize

  helper :sort
  include SortHelper
  helper :search # for highlight_tokens in the Account Holder Access report

  def index
    # Report selection/navigation page
  end

  def daily
    @mode = params[:mode] == 'range' ? 'range' : 'business_day'

    if @mode == 'business_day'
      selected_date = parse_date_param(params[:end_date])&.to_date || Date.current
      from_date, to_date = NysenateAuditUtils::Reporting::DailyReportService.business_day_range(selected_date)
    else
      from_date = parse_date_param(params[:start_date]) || Date.yesterday.to_time
      to_date   = parse_date_param(params[:end_date])   || Date.current.to_time
    end

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
      'status_changes' => 'status_changes',
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
      format.html { paginate_report_data }
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data csv_data,
                  filename: "daily_report_#{Date.today.strftime('%Y%m%d')}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
      format.xlsx do
        xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_daily_xlsx(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data xlsx_data,
                  filename: "daily_report_#{Date.today.strftime('%Y%m%d')}.xlsx",
                  type: Mime[:xlsx].to_s,
                  disposition: 'attachment'
      end
    end
  rescue ArgumentError => e
    # Handle validation errors
    flash.now[:error] = e.message
    @mode ||= 'business_day'
    @from_date, @to_date = NysenateAuditUtils::Reporting::DailyReportService.business_day_range(Date.current)
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
      'user_type' => 'user_type',
      'request_code' => 'request_code',
      'updated_on' => 'updated_on',
      'created_on' => 'created_on',
      'closed_on' => 'closed_on'
    })

    # Apply sorting to report data
    @report_data = sort_report_data(@report_data) if @report_data.present?

    respond_to do |format|
      format.html { paginate_report_data }
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_weekly_csv(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data csv_data,
                  type: 'text/csv; header=present',
                  filename: "weekly_report_#{Date.current.strftime('%Y%m%d')}.csv"
      end
      format.xlsx do
        xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_weekly_xlsx(
          @report_data, from_date: @from_date, to_date: @to_date
        )
        send_data xlsx_data,
                  type: Mime[:xlsx].to_s,
                  filename: "weekly_report_#{Date.current.strftime('%Y%m%d')}.xlsx",
                  disposition: 'attachment'
      end
    end
  rescue => e
    Rails.logger.error "Weekly report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
    render :error
  end

  # Quarterly / Annual audit report: closed SFMS or SFS tickets over an audit
  # window. Feeds the SFMS Quarterly Audit and the SFS Annual Audit.
  def periodic
    service_class = NysenateAuditUtils::Reporting::PeriodicAuditReportService
    @system = params[:system] == 'sfs' ? :sfs : :sfms

    # Offset-quarter options for the SFMS picker
    @sfms_quarters = service_class.recent_sfms_quarters(8)

    @from_date, @to_date = resolve_periodic_window(service_class)

    service = service_class.new(
      project: @project,
      system: @system,
      from_date: @from_date,
      to_date: @to_date
    )
    @report_data = service.generate
    @target_systems = service.target_systems

    unless service.success?
      @error_message = service.errors.join('; ')
      render :error
      return
    end

    sort_init 'closed_on', 'desc'
    sort_update({
      'request_code' => 'request_code',
      'user_name' => 'user_name',
      'user_uid' => 'user_uid',
      'office' => 'office',
      'created_on' => 'created_on',
      'closed_on' => 'closed_on',
      'bac_number' => 'bac_number',
      'issue_id' => 'issue_id',
      'subject' => 'subject'
    })
    @report_data = sort_report_data(@report_data) if @report_data.present?

    respond_to do |format|
      format.html { paginate_report_data }
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_periodic_csv(
          @report_data, system: @system, from_date: @from_date, to_date: @to_date
        )
        send_data csv_data,
                  type: 'text/csv; header=present',
                  filename: "#{@system}_audit_#{@from_date.strftime('%Y%m%d')}_#{@to_date.strftime('%Y%m%d')}.csv"
      end
      format.xlsx do
        xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_periodic_xlsx(
          @report_data, system: @system, from_date: @from_date, to_date: @to_date
        )
        send_data xlsx_data,
                  type: Mime[:xlsx].to_s,
                  filename: "#{@system}_audit_#{@from_date.strftime('%Y%m%d')}_#{@to_date.strftime('%Y%m%d')}.xlsx",
                  disposition: 'attachment'
      end
    end
  rescue => e
    Rails.logger.error "Periodic report generation failed: #{e.message}"
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
    sort_init 'user_name', 'asc'
    sort_update({
      'user_name' => 'user_name',
      'user_id' => 'user_id',
      'user_type' => 'user_type',
      'user_uid' => 'user_uid',
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
      format.html { paginate_report_data }
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
      format.xlsx do
        xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_monthly_xlsx(
          @report_data, as_of_time: @as_of_time, target_system: target_system
        )
        filename_suffix = if mode == 'current'
                            'current'
                          else
                            "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
                          end
        send_data xlsx_data,
                  filename: "monthly_report_#{target_system.parameterize}_#{filename_suffix}.xlsx",
                  type: Mime[:xlsx].to_s,
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

    if params[:format].to_s == 'xlsx'
      xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_all_systems_xlsx(
        reports_by_system, as_of_time: as_of_time
      )
      send_data xlsx_data,
                filename: "monthly_reports_all_systems_#{filename_suffix}.xlsx",
                type: Mime[:xlsx].to_s,
                disposition: 'attachment'
    else
      zip_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_all_systems_zip(
        reports_by_system, filename_suffix, as_of_time: as_of_time
      )
      send_data zip_data,
                filename: "monthly_reports_all_systems_#{filename_suffix}.zip",
                type: 'application/zip',
                disposition: 'attachment'
    end
  rescue => e
    Rails.logger.error "Monthly ZIP export failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate ZIP export: #{e.message}"
    render :error
  end

  # Account Holder Access Report: all currently active account access across
  # every target system, one row per account holder x system, ordered by name.
  def account_holder_access
    # Filters (applied to the flat rows before grouping/CSV so both the web view
    # and the CSV export reflect them). Blank search / blank type = no filtering.
    @search = params[:search].to_s.strip
    @user_type_filter = params[:user_type].presence
    @target_system_filter = params[:target_system].presence
    # Account access status: default to active only (preserves prior behavior);
    # 'all' shows active + inactive, 'inactive' shows inactive only.
    @account_status_filter = params[:account_status].presence || 'active'

    service = NysenateAuditUtils::Reporting::AccountHolderAccessReportService.new(project: @project)
    @report_data = service.generate

    unless service.success?
      @error_message = service.errors.join('; ')
      render :error
      return
    end

    sort_init 'user_name', 'asc'
    # Only holder-level columns are sortable; target system / request code are
    # squished into a single grouped row in the web view, so they aren't sorted.
    sort_update({
      'user_name' => 'user_name',
      'user_type' => 'user_type',
      'user_uid' => 'user_uid',
      'user_office' => 'user_office'
    })

    @report_data = sort_report_data(@report_data) if @report_data.present?
    @report_data = filter_account_holder_access_data(@report_data) if @report_data.present?

    respond_to do |format|
      format.html do
        # Total accounts = flat row count, before collapsing to one row per holder.
        @account_count = @report_data.size
        # Collapse to one row per account holder for the web view only.
        @report_data = group_report_data_by_holder(@report_data)
        paginate_report_data
      end
      format.csv do
        csv_data = NysenateAuditUtils::Reporting::CsvGenerator.generate_account_holder_access_csv(@report_data)
        send_data csv_data,
                  filename: "account_holder_access_report_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
      format.xlsx do
        xlsx_data = NysenateAuditUtils::Reporting::XlsxGenerator.generate_account_holder_access_xlsx(@report_data)
        send_data xlsx_data,
                  filename: "account_holder_access_report_#{Date.current.strftime('%Y%m%d')}.xlsx",
                  type: Mime[:xlsx].to_s,
                  disposition: 'attachment'
      end
    end
  rescue => e
    Rails.logger.error "Account Holder Access report generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = "Unable to generate report: #{e.message}"
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

  # Resolve the [from, to] window for the periodic (quarterly/annual) report.
  # The start_date/end_date pickers are the single source of truth (the SFMS
  # quarter dropdown is a front-end helper that fills those pickers).
  #   SFS:  end date drives it; start auto-fills to one year prior (inclusive)
  #         unless overridden.
  #   SFMS: an explicit start+end window, else the most recent offset quarter.
  def resolve_periodic_window(service_class)
    start_param = parse_date_param(params[:start_date])
    end_param   = parse_date_param(params[:end_date])

    if @system == :sfs
      if end_param
        from = start_param || service_class.sfs_start_for(end_param.to_date).to_time
        return [from.beginning_of_day, end_param.end_of_day]
      end
    elsif start_param && end_param
      return [start_param.beginning_of_day, end_param.end_of_day]
    end

    window = service_class.default_window(@system)
    [window[:from], window[:to]]
  end

  def validate_date_range!(from_date, to_date)
    # Ensure from_date is before to_date
    if from_date > to_date
      raise ArgumentError, "Start date must be before end date"
    end

    # Allow dates up to tomorrow
    today = Date.current
    tomorrow = today + 1.day

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

  # Paginate the in-memory report rows for HTML display only.
  # Preserves the full row count in @report_count (for pagination links and
  # the "Showing N" line) and replaces @report_data with the current page
  # slice. Must be called inside the format.html block so CSV keeps the full
  # dataset.
  def paginate_report_data
    @report_data ||= []
    @report_count = @report_data.size
    @report_pages = Redmine::Pagination::Paginator.new(
      @report_count, per_page_option, params['page']
    )
    @report_data = @report_data[@report_pages.offset, @report_pages.per_page] || []
  end

  # Collapse the flat per-account rows into one row per account holder for the
  # HTML view. Each holder keeps a single name/type/username and carries a list
  # of its (target system, request code) accounts. Order is preserved from the
  # already-sorted input. The CSV export keeps the flat one-row-per-account
  # layout (this is only applied in the HTML branch).
  # Apply the Account Holder Access report filters (search + type) to the flat
  # per-account rows. Runs before the HTML grouping and before the CSV is built,
  # so both outputs honour the same filtered set.
  def filter_account_holder_access_data(rows)
    rows = rows.select { |r| holder_type_match?(r[:user_type]) } if @user_type_filter
    rows = rows.select { |r| r[:account_type] == @target_system_filter } if @target_system_filter
    rows = rows.select { |r| r[:status] == @account_status_filter } unless @account_status_filter == 'all'
    if @search.present?
      q = @search.downcase
      rows = rows.select do |r|
        r[:user_name].to_s.downcase.include?(q) ||
          r[:user_uid].to_s.downcase.include?(q)
      end
    end
    rows
  end

  # "Non-employee" matches any type that is not Employee; the other options are
  # exact matches on the Account Holder Type value.
  def holder_type_match?(user_type)
    case @user_type_filter
    when 'non_employee' then user_type.to_s != 'Employee'
    else user_type.to_s == @user_type_filter
    end
  end

  def group_report_data_by_holder(rows)
    grouped = {}
    rows.each do |row|
      key = row[:user_id]
      grouped[key] ||= {
        user_name: row[:user_name],
        user_type: row[:user_type],
        user_uid: row[:user_uid],
        user_office: row[:user_office],
        user_id: row[:user_id],
        accounts: []
      }
      grouped[key][:accounts] << {
        account_type: row[:account_type],
        request_code: row[:request_code],
        status: row[:status],
        issue_id: row[:issue_id]
      }
    end
    grouped.values
  end

  def sort_report_data(data)
    return data unless @sort_criteria

    sort_key = @sort_criteria.first_key
    # Guard against stale/invalid sort keys (e.g. left over in the session from
    # before a column rename). If the key isn't an actual column in the data,
    # fall back to the default sort so the data isn't left unsorted.
    unless @sortable_columns&.key?(sort_key)
      sort_key = @sort_default.first.first
    end
    sort_order = @sort_criteria.first_asc? ? 1 : -1

    data.sort do |a, b|
      a_val = a[sort_key.to_sym]
      b_val = b[sort_key.to_sym]

      # status_changes is an array of {code:, note:}; sort by joined codes
      if sort_key.to_sym == :status_changes
        a_val = a_val.is_a?(Array) ? a_val.map { |c| c[:code] }.join(',') : a_val
        b_val = b_val.is_a?(Array) ? b_val.map { |c| c[:code] }.join(',') : b_val
      end

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