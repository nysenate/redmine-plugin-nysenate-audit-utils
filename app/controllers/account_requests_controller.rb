# frozen_string_literal: true

# Launches a pre-filled new-issue form for an account holder straight from the
# daily report (feature #18134, Phase 1). Standalone controller (like
# PacketCreationController) — it does not patch or subclass core IssuesController.
# It re-fetches the employee from ESS, maps the data to the Account Holder custom
# fields, and redirects to core's GET issues/new with those values pre-filled.
class AccountRequestsController < ApplicationController
  before_action :find_project
  before_action :authorize_account_request

  def new
    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(params[:employee_id])
    tracker = detect_tracker

    if employee
      cf_values = NysenateAuditUtils::Autofill::EmployeeMapper.map_employee_to_field_values(employee)
    else
      cf_values = {}
      flash[:warning] = l(:warning_account_request_employee_not_found, id: params[:employee_id])
    end

    redirect_to new_project_issue_path(
      @project,
      issue: { tracker_id: tracker&.id, custom_field_values: cf_values }
    )
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Own authorization (don't call core `authorize`, which would look up a
  # non-existent permission mapping for account_requests#new and deny).
  def authorize_account_request
    unless @project.module_enabled?(:audit_utils) &&
           User.current.allowed_to?(:add_issues, @project)
      render_403
    end
  end

  # Pick the project's tracker whose custom fields include the configured
  # Account Holder fields (same heuristic as Autofill::Hooks#has_user_fields?),
  # falling back to the project's first tracker.
  def detect_tracker
    field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids.values
    @project.trackers.detect { |t| field_ids.intersect?(t.custom_fields.pluck(:id)) } ||
      @project.trackers.first
  end
end
