# frozen_string_literal: true

class UserSearchController < ApplicationController
  before_action :require_login
  before_action :check_permission

  VALID_TYPES = %w[Employee Vendor].freeze
  DEFAULT_TYPE = 'Employee'

  def search
    if params[:q].blank?
      render json: { users: [], message: "Search query cannot be empty" }, status: :bad_request
      return
    end

    begin
      query = sanitize_search_query(params[:q])
      user_type = params[:type].presence || DEFAULT_TYPE
      offset = params[:offset].to_i
      limit = params[:limit].to_i
      limit = 20 if limit <= 0 || limit > 100

      # Validate user type
      unless VALID_TYPES.include?(user_type)
        render json: {
          error: "Invalid user type. Must be one of: #{VALID_TYPES.join(', ')}",
          users: []
        }, status: :bad_request
        return
      end

      tracked_users = perform_user_search(query, user_type, limit, offset)

      render json: {
        users: tracked_users,
        total: tracked_users.length,
        offset: offset,
        limit: limit,
        has_more: tracked_users.length == limit,
        type: user_type
      }
    rescue => e
      logger.error "User search error: #{e.message}"
      logger.error e.backtrace.join("\n")
      render json: {
        error: "User search temporarily unavailable. Please try again later.",
        users: []
      }, status: :service_unavailable
    end
  end

  def field_mappings
    begin
      # Get field IDs from unified configuration
      field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids

      # Build field ID mappings for the frontend in Redmine's expected format
      # Converts { user_id: 123, name: 124 } to { user_id_field: "issue_custom_field_values_123", ... }
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
    unless project && project.module_enabled?(:audit_utils)
      render json: { error: "Access denied" }, status: :forbidden
      return
    end

    # Check if user has permission for this project
    unless User.current.allowed_to?(:use_user_autofill, project)
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

  def perform_user_search(query, user_type, limit, offset)
    service = NysenateAuditUtils::Users::UserService.new
    service.search(query, type: user_type, limit: limit, offset: offset)
  end
end
