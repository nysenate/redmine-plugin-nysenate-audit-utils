# frozen_string_literal: true

require 'stringio'

# Launches a pre-filled new-issue form for an account holder straight from the
# daily report (feature #18134).
#
# Subclass of core IssuesController (a separate controller with its own route and
# filters — not a monkeypatch). It reuses core's new-issue machinery so it can:
#   * pre-fill the Account Holder custom fields from ESS employee data, and
#   * seed the daily report itself as a *pending* (unsaved) attachment, rendered
#     natively by core's attachments form, attached by core's create on save.
class AccountRequestsController < IssuesController
  # Re-order the inherited filter chain. We skip core's find_optional_project
  # (it calls authorize_global, which denies because account_requests#new has no
  # registered permission) and own project-finding + authorization ourselves, then
  # let the inherited build_new_issue_from_params run after our gate passes.
  skip_before_action :find_optional_project, only: [:new]
  skip_before_action :build_new_issue_from_params, only: [:new]
  before_action :authorize_account_request, only: [:new]
  before_action :build_new_issue_from_params, only: [:new]

  # By the time this runs, authorize_account_request has set @project and the
  # inherited build_new_issue_from_params has set @issue, @priorities and
  # @allowed_statuses from params.
  def new
    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(params[:employee_id])

    if employee
      @issue.safe_attributes = {
        'tracker_id' => detect_tracker&.id,
        'custom_field_values' => NysenateAuditUtils::Autofill::EmployeeMapper.map_employee_to_field_values(employee)
      }
      # Recompute allowed statuses for the (possibly changed) tracker.
      @allowed_statuses = @issue.new_statuses_allowed_to(User.current)
      attach_daily_report
    else
      flash.now[:warning] = l(:warning_account_request_employee_not_found, id: params[:employee_id])
    end

    render 'issues/new'
  end

  private

  def authorize_account_request
    @project ||= Project.find(params[:project_id])
    unless @project.module_enabled?(:audit_utils) &&
           User.current.allowed_to?(:add_issues, @project)
      render_403
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Pick the project's tracker whose custom fields include the configured
  # Account Holder fields (same heuristic as Autofill::Hooks#has_user_fields?),
  # falling back to the project's first tracker.
  def detect_tracker
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids.values
    @project.trackers.detect { |t| field_ids.intersect?(t.custom_fields.pluck(:id)) } ||
      @project.trackers.first
  end

  # Regenerate the full daily report for the date range carried by the button and
  # seed it as a container-less (tokenable) pending attachment on the new issue.
  # Never blocks ticket creation: any failure is logged and the form still renders.
  def attach_daily_report
    from = parse_time(params[:from_date])
    to   = parse_time(params[:to_date])
    return unless from && to

    service = NysenateAuditUtils::Reporting::DailyReportService.new(
      from_date: from, to_date: to, project: @project
    )
    rows = service.generate
    return unless service.success? && rows.present?

    csv = NysenateAuditUtils::Reporting::CsvGenerator.generate_daily_csv(
      rows, from_date: from, to_date: to
    )

    attachment = Attachment.new(
      file: StringIO.new(csv),
      filename: "daily_report_#{to.to_date.strftime('%Y%m%d')}.csv",
      content_type: 'text/csv',
      author: User.current
    )
    # No container -> container-less -> resolvable later via Attachment.find_by_token.
    @issue.saved_attachments << attachment if attachment.save
  rescue StandardError => e
    Rails.logger.warn("[nysenate_audit_utils] daily report attach failed: #{e.class}: #{e.message}")
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
