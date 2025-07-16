class PacketCreationController < ApplicationController
  include Redmine::Export::PDF::IssuesPdfHelper
  include CustomFieldsHelper
  include IssuesHelper
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  include Rails.application.routes.url_helpers
  
  before_action :find_issue
  before_action :authorize_packet_creation
  
  def create
    begin
      Rails.logger.info "Creating packet for issue #{@issue.id} by user #{User.current.id}"
      
      # Generate PDF using the same approach as core Redmine
      # Set up the same instance variables that the PDF template expects
      @journals = @issue.journals.visible.preload(:user, :details)
      
      # Generate PDF directly in controller context with proper helper inclusion
      pdf_content = issue_to_pdf(@issue, journals: @journals)
      
      # Use the service to create the zip with PDF and attachments
      service = PacketCreationService.new(@issue)
      packet_zip = service.create_packet_with_pdf(pdf_content)
      
      send_data packet_zip,
                filename: "packet_#{@issue.id}.zip",
                type: 'application/zip',
                disposition: 'attachment'
                
      Rails.logger.info "Packet created successfully for issue #{@issue.id}"
      
    rescue => e
      Rails.logger.error "Packet creation failed for issue #{@issue.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      flash[:error] = l(:error_packet_creation_failed)
      redirect_to issue_path(@issue)
    end
  end
  
  private
  
  def find_issue
    @issue = Issue.find(params[:id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def authorize_packet_creation
    unless @issue.visible?(User.current)
      render_404
      return
    end
    unless @issue.attachments_visible?(User.current)
      flash[:error] = l(:notice_not_authorized)
      redirect_to issue_path(@issue)
      return
    end
  end
  
  # Provide the h method alias for HTML escaping (used by view helpers)
  def h(text)
    ERB::Util.html_escape(text)
  end
  
  # Provide url_for method for PDF generation (links in PDFs don't work anyway)
  def url_for(options = {})
    # Since PDF links aren't clickable, return a placeholder or the raw URL
    case options
    when String
      options
    when Hash
      if options[:controller] && options[:action]
        "##{options[:controller]}/#{options[:action]}"
      else
        "#"
      end
    else
      "#"
    end
  end
  
end