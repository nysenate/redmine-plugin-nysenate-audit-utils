# frozen_string_literal: true

# Controller for managing non-employee subjects (Vendors, etc.)
# Provides CRUD operations for project users with manage_subjects permission
class SubjectsController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :set_subject, only: [:edit, :update, :destroy]

  # GET /projects/:project_id/subjects
  def index
    @limit = per_page_option
    @subjects_count = Subject.count
    @subjects_pages = Paginator.new @subjects_count, @limit, params[:page]
    @offset ||= @subjects_pages.offset
    @subjects = Subject.order(:subject_type, :subject_id).limit(@limit).offset(@offset).to_a
  end

  # GET /projects/:project_id/subjects/new
  def new
    @subject = Subject.new(status: 'Active', subject_type: 'Vendor')

    # Auto-generate next vendor ID if type is Vendor
    if @subject.subject_type == 'Vendor'
      @subject.subject_id = Subject.next_vendor_id
    end
  end

  # POST /projects/:project_id/subjects
  def create
    @subject = Subject.new(subject_params)

    if @subject.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_subjects_path(@project)
    else
      render :new
    end
  rescue => e
    logger.error "Error creating subject: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash.now[:error] = "An error occurred while creating the subject: #{e.message}"
    render :new
  end

  # GET /projects/:project_id/subjects/:id/edit
  def edit
    # @subject set by before_action
  end

  # PATCH/PUT /projects/:project_id/subjects/:id
  def update
    if @subject.update(subject_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_subjects_path(@project)
    else
      render :edit
    end
  rescue => e
    logger.error "Error updating subject: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash.now[:error] = "An error occurred while updating the subject: #{e.message}"
    render :edit
  end

  # DELETE /projects/:project_id/subjects/:id
  def destroy
    if @subject.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = "Failed to delete subject: #{@subject.errors.full_messages.join(', ')}"
    end
    redirect_to project_subjects_path(@project)
  rescue => e
    logger.error "Error deleting subject: #{e.message}"
    logger.error e.backtrace.join("\n")
    flash[:error] = "An error occurred while deleting the subject: #{e.message}"
    redirect_to project_subjects_path(@project)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def set_subject
    @subject = Subject.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def subject_params
    params.require(:subject).permit(
      :subject_type,
      :subject_id,
      :name,
      :email,
      :phone,
      :uid,
      :location,
      :status
    )
  end
end
