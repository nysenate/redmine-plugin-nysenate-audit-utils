# frozen_string_literal: true

class PacketCreationService
  def initialize(issue)
    @issue = issue
  end

  def create_packet_with_pdf(pdf_content)
    create_combined_zip(pdf_content, @issue.attachments)
  end

  # Legacy method for backward compatibility - will be removed
  def create_packet
    raise NotImplementedError, "Use create_packet_with_pdf instead - PDF generation moved to controller"
  end

  private

  def create_combined_zip(pdf_content, attachments)
    require 'zip'
    
    Zip::OutputStream.write_buffer do |zos|
      # Add PDF as first entry
      zos.put_next_entry("ticket_#{@issue.id}.pdf")
      zos.write(pdf_content)
      
      # Add attachments with duplicate name handling
      archived_filenames = ["ticket_#{@issue.id}.pdf"]
      
      attachments.each do |attachment|
        next unless attachment.readable?
        
        begin
          filename = ensure_unique_filename(attachment.filename, archived_filenames)
          archived_filenames << filename
          
          zos.put_next_entry(filename)
          zos.write(IO.binread(attachment.diskfile))
          
        rescue => e
          Rails.logger.warn "Failed to add attachment #{attachment.filename} to packet: #{e.message}"
          # Continue with other attachments
        end
      end
    end.string
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