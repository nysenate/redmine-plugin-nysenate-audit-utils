# frozen_string_literal: true

module PacketCreationService
  require 'zip'

  # Create a packet for a single issue
  def self.create_packet(issue, pdf_content)
    create_zip_with_attachments(issue, pdf_content, issue.attachments)
  end

  # Create a multi-packet ZIP with multiple issues
  def self.create_multi_packet(issues, pdf_contents_by_issue_id)
    validate_multi_packet_inputs(issues, pdf_contents_by_issue_id)
    
    Zip::OutputStream.write_buffer do |zos|
      issues.each do |issue|
        pdf_content = pdf_contents_by_issue_id[issue.id]
        raise "Missing PDF content for issue #{issue.id}" unless pdf_content
        
        add_issue_packet_to_zip(zos, issue, pdf_content)
      end
    end.string
  end

  private

  def self.validate_multi_packet_inputs(issues, pdf_contents_by_issue_id)
    raise ArgumentError, "No issues provided" if issues.empty?
    
    issues.each do |issue|
      unless pdf_contents_by_issue_id[issue.id]
        raise "Missing PDF content for issue #{issue.id}"
      end
    end
  end

  def self.add_issue_packet_to_zip(zos, issue, pdf_content)
    packet_dir = "packet_#{issue.id}"
    archived_filenames = []
    
    # Add PDF as first entry in the packet directory
    pdf_filename = "#{packet_dir}/ticket_#{issue.id}.pdf"
    zos.put_next_entry(pdf_filename)
    zos.write(pdf_content)
    archived_filenames << "ticket_#{issue.id}.pdf"
    
    # Add attachments with duplicate name handling
    add_attachments_to_zip(zos, issue.attachments, archived_filenames, packet_dir)
  end

  def self.create_zip_with_attachments(issue, pdf_content, attachments)
    Zip::OutputStream.write_buffer do |zos|
      # Add PDF as first entry
      zos.put_next_entry("ticket_#{issue.id}.pdf")
      zos.write(pdf_content)
      
      # Add attachments with duplicate name handling
      archived_filenames = ["ticket_#{issue.id}.pdf"]
      add_attachments_to_zip(zos, attachments, archived_filenames)
    end.string
  end

  def self.add_attachments_to_zip(zos, attachments, archived_filenames, prefix = nil)
    attachments.each do |attachment|
      next unless attachment.readable?
      
      begin
        filename = ensure_unique_filename(attachment.filename, archived_filenames)
        archived_filenames << filename
        
        entry_name = prefix ? "#{prefix}/#{filename}" : filename
        zos.put_next_entry(entry_name)
        zos.write(IO.binread(attachment.diskfile))
        
      rescue => e
        Rails.logger.warn "Failed to add attachment #{attachment.filename}: #{e.message}"
        if prefix
          raise "Failed to process attachment #{attachment.filename}: #{e.message}"
        end
        # Continue with other attachments for single packet
      end
    end
  end

  def self.ensure_unique_filename(filename, existing_names)
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