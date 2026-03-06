# frozen_string_literal: true

class SubjectSearchController < ApplicationController
  before_action :require_login
  before_action :check_permission

  VALID_TYPES = %w[Employee Vendor].freeze
  DEFAULT_TYPE = 'Employee'

  def search
    if params[:q].blank?
      render json: { subjects: [], message: "Search query cannot be empty" }, status: :bad_request
      return
    end

    begin
      query = sanitize_search_query(params[:q])
      subject_type = params[:type].presence || DEFAULT_TYPE
      offset = params[:offset].to_i
      limit = params[:limit].to_i
      limit = 20 if limit <= 0 || limit > 100

      # Validate subject type
      unless VALID_TYPES.include?(subject_type)
        render json: {
          error: "Invalid subject type. Must be one of: #{VALID_TYPES.join(', ')}",
          subjects: []
        }, status: :bad_request
        return
      end

      subjects = perform_subject_search(query, subject_type, limit, offset)

      render json: {
        subjects: subjects,
        total: subjects.length,
        offset: offset,
        limit: limit,
        has_more: subjects.length == limit,
        type: subject_type
      }
    rescue => e
      logger.error "Subject search error: #{e.message}"
      logger.error e.backtrace.join("\n")
      render json: {
        error: "Subject search temporarily unavailable. Please try again later.",
        subjects: []
      }, status: :service_unavailable
    end
  end

  def field_mappings
    begin
      # Get field IDs from unified configuration
      field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

      # Build field ID mappings for the frontend in Redmine's expected format
      # Converts { subject_id: 123, name: 124 } to { subject_id_field: "issue_custom_field_values_123", ... }
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
    project = find_project

    # Check if project exists and module is enabled
    unless project && project.module_enabled?(:audit_utils_subject_autofill)
      render json: { error: "Access denied" }, status: :forbidden
      return
    end

    # Check if user has permission for this project
    unless User.current.allowed_to?(:use_subject_autofill, project)
      render json: { error: "Access denied" }, status: :forbidden
    end
  end

  def find_project
    return nil unless params[:project_id].present?

    Project.find_by(id: params[:project_id])
  end

  def sanitize_search_query(query)
    query.to_s.strip.gsub(/[<>'"&]/, '').first(100)
  end

  def perform_subject_search(query, subject_type, limit, offset)
    service = NysenateAuditUtils::Subjects::SubjectService.new
    service.search(query, type: subject_type, limit: limit, offset: offset)
  end
end
