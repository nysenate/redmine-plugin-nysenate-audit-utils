class EmployeeSearchController < ApplicationController
  before_action :require_login
  before_action :check_permission

  def search
    if params[:q].blank?
      render json: { employees: [], message: "Search query cannot be empty" }, status: :bad_request
      return
    end

    begin
      query = sanitize_search_query(params[:q])
      offset = params[:offset].to_i
      limit = params[:limit].to_i
      limit = 20 if limit <= 0 || limit > 100

      employees = perform_employee_search(query, limit, offset)
      mapped_employees = employees.map { |emp| map_employee_data(emp) }

      render json: {
        employees: mapped_employees,
        total: mapped_employees.length,
        offset: offset,
        limit: limit,
        has_more: mapped_employees.length == limit
      }
    rescue => e
      logger.error "Employee search error: #{e.message}"
      logger.error e.backtrace.join("\n")
      render json: {
        error: "Employee search temporarily unavailable. Please try again later.",
        employees: []
      }, status: :service_unavailable
    end
  end

  def field_mappings
    begin
      # Get field IDs from unified configuration
      field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

      # Build field ID mappings for the frontend in Redmine's expected format
      # Converts { employee_id: 123, name: 124 } to { employee_id_field: "issue_custom_field_values_123", ... }
      mappings = {}
      field_ids.each do |key, field_id|
        if field_id
          # Add _field suffix to match frontend expectations
          frontend_key = "#{key}_field"
          mappings[frontend_key] = "issue_custom_field_values_#{field_id}"
        end
      end

      render json: { field_mappings: mappings }
    rescue => e
      logger.error "Field mappings error: #{e.message}"
      render json: { error: "Could not load field mappings" }, status: :internal_server_error
    end
  end

  private

  def check_permission
    unless User.current.allowed_to?(:use_employee_autofill, nil, global: true)
      render json: { error: "Access denied" }, status: :forbidden
    end
  end

  def sanitize_search_query(query)
    query.to_s.strip.gsub(/[<>'"&]/, '').first(100)
  end

  def perform_employee_search(query, limit, offset)
    NysenateAuditUtils::Ess::EssEmployeeService.search(query, limit: limit, offset: offset)
  end

  def map_employee_data(employee)
    NysenateAuditUtils::Autofill::EmployeeMapper.map_employee(employee)
  end
end