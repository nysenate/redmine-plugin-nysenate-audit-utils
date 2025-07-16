# frozen_string_literal: true

class MultiPacketCreationService
  def initialize(issues)
    @issues = issues
  end

  def create_multi_packet_with_pdfs(pdf_contents_by_issue_id)
    validate_inputs(pdf_contents_by_issue_id)
    
    require 'zip'
    
    Zip::OutputStream.write_buffer do |zos|
      @issues.each do |issue|
        pdf_content = pdf_contents_by_issue_id[issue.id]
        raise "Missing PDF content for issue #{issue.id}" unless pdf_content
        
        create_issue_packet_in_zip(zos, issue, pdf_content)
      end
    end.string
  end

  private

  def validate_inputs(pdf_contents_by_issue_id)
    raise ArgumentError, "No issues provided" if @issues.empty?
    
    @issues.each do |issue|
      unless User.current.allowed_to?(:view_issues, issue.project)
        raise "Permission denied for issue #{issue.id}"
      end
      
      unless pdf_contents_by_issue_id[issue.id]
        raise "Missing PDF content for issue #{issue.id}"
      end
    end
  end

  def create_issue_packet_in_zip(zos, issue, pdf_content)
    packet_dir = "packet_#{issue.id}"
    archived_filenames = []
    
    # Add PDF as first entry in the packet directory
    pdf_filename = "#{packet_dir}/ticket_#{issue.id}.pdf"
    zos.put_next_entry(pdf_filename)
    zos.write(pdf_content)
    archived_filenames << "ticket_#{issue.id}.pdf"
    
    # Add attachments with duplicate name handling
    issue.attachments.each do |attachment|
      next unless attachment.readable?
      
      begin
        filename = ensure_unique_filename(attachment.filename, archived_filenames)
        archived_filenames << filename
        
        zos.put_next_entry("#{packet_dir}/#{filename}")
        zos.write(IO.binread(attachment.diskfile))
        
      rescue => e
        Rails.logger.warn "Failed to add attachment #{attachment.filename} to packet #{issue.id}: #{e.message}"
        raise "Failed to process attachment #{attachment.filename} for issue #{issue.id}: #{e.message}"
      end
    end
  end

  def ensure_unique_filename(filename, existing_names)
    return filename unless existing_names.include?(filename)
    
    dup_count = 1
    extname = File.extname(filename)
    basename = File.basename(filename, extname)
    
    loop do
      new_filename = "#{basename}(#{dup_count})#{extname}"
      return new_filename unless existing_names.include?(new_filename)
      dup_count += 1
    end
  end
end