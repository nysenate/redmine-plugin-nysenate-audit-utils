# frozen_string_literal: true

# Controller for managing non-employee tracked users (Vendors, etc.)
# Provides CRUD operations for project users with manage_tracked_users permission
class TrackedUsersController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :set_tracked_user, only: [:edit, :update, :destroy]

  # GET /projects/:project_id/tracked_users
  def index
    @limit = per_page_option
    @tracked_users_count = TrackedUser.count
    @tracked_users_pages = Paginator.new @tracked_users_count, @limit, params[:page]
    @offset ||= @tracked_users_pages.offset
    @tracked_users = TrackedUser.order(:user_type, :user_id).limit(@limit).offset(@offset).to_a
  end

  # GET /projects/:project_id/tracked_users/new
  def new
    @tracked_user = TrackedUser.new(status: 'Active', user_type: 'Vendor')
    @tracked_user.user_id = TrackedUser.next_tracked_user_id
  end

  # POST /projects/:project_id/tracked_users
  def create
    @tracked_user = TrackedUser.new(tracked_user_params)

    if @tracked_user.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_tracked_users_path(@project)
    else
      render :new
    end
  rescue => e
    logger.error "Error creating tracked user: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash.now[:error] = "An error occurred while creating the tracked user: #{e.message}"
    render :new
  end

  # GET /projects/:project_id/tracked_users/:id/edit
  def edit
    # @tracked_user set by before_action
  end

  # PATCH/PUT /projects/:project_id/tracked_users/:id
  def update
    if @tracked_user.update(tracked_user_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_tracked_users_path(@project)
    else
      render :edit
    end
  rescue => e
    logger.error "Error updating tracked user: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash.now[:error] = "An error occurred while updating the tracked user: #{e.message}"
    render :edit
  end

  # DELETE /projects/:project_id/tracked_users/:id
  def destroy
    if @tracked_user.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = "Failed to delete tracked user: #{@tracked_user.errors.full_messages.join(', ')}"
    end
    redirect_to project_tracked_users_path(@project)
  rescue => e
    logger.error "Error deleting tracked user: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred while deleting the tracked user: #{e.message}"
    redirect_to project_tracked_users_path(@project)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def set_tracked_user
    @tracked_user = TrackedUser.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def tracked_user_params
    params.require(:tracked_user).permit(
      :user_type,
      :user_id,
      :name,
      :email,
      :phone,
      :uid,
      :location,
      :status
    )
  end
end
