# BACHelp Packet Creation Plugin - Technical Considerations

## Overview

This document outlines the technical approach for implementing packet creation functionality by leveraging existing Redmine infrastructure rather than building custom solutions.

## PDF Generation

### Existing Redmine Infrastructure

Redmine provides a robust PDF generation system through the `Redmine::Export::PDF::IssuesPdfHelper` module located at `lib/redmine/export/pdf/issues_pdf_helper.rb`.

#### Key Method: `issue_to_pdf`

```ruby
def issue_to_pdf(issue, assoc={})
  # Returns PDF string of complete issue information
end
```

**Features included:**
- Complete issue metadata (status, priority, assigned user, etc.)
- Custom fields (both inline and full-width layout)
- Issue description with proper formatting
- Subtasks and related issues
- Change history/journals when `assoc[:journals]` provided
- Associated revisions/changesets
- Attachment listings with metadata
- Proper internationalization support
- Consistent styling with Redmine theme

#### Integration Approach

```ruby
class PacketCreationController < ApplicationController
  include Redmine::Export::PDF::IssuesPdfHelper
  
  def create
    # Generate PDF with full history
    pdf_content = issue_to_pdf(@issue, {journals: @issue.journals})
    # pdf_content is a string containing the complete PDF
  end
end
```

#### Advantages

1. **Consistency**: Same PDF output as Redmine's built-in export functionality
2. **Completeness**: Includes all issue data, custom fields, and formatting
3. **Maintenance**: Automatically benefits from Redmine core improvements
4. **Internationalization**: Supports all languages that Redmine supports
5. **Custom Fields**: Properly handles all custom field types and layouts
6. **No Dependencies**: Uses existing Redmine PDF infrastructure (ITCPDF)

## Zip File Creation

### Analysis of redmine_issue_attachments Plugin

The existing `redmine_issue_attachments` plugin demonstrates one approach to zip creation, but has several limitations:

**Current Plugin Approach (Not Recommended):**
```ruby
# Uses temporary files - resource management issues
zip_file = Tempfile.new(["attachments", ".zip"], binmode: true)
Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
  attachments.each do |attachment|
    zip.add(attachment.filename.to_s, attachment.diskfile)
  end
end
send_file zip_file.path, filename: "attachments.zip", type: "application/zip"
```

**Issues with this approach:**
- Manual temporary file management
- No explicit cleanup of temp files
- No handling of duplicate filenames
- Limited error handling
- Uses file system instead of memory

### Recommended Approach: Redmine Core Infrastructure

Redmine core provides a superior zip creation method in the `Attachment` model:

#### Key Method: `Attachment.archive_attachments`

```ruby
def self.archive_attachments(attachments)
  attachments = attachments.select(&:readable?)
  return nil if attachments.blank?

  Zip.unicode_names = true
  archived_file_names = []
  buffer = Zip::OutputStream.write_buffer do |zos|
    attachments.each do |attachment|
      filename = attachment.filename
      # Handle duplicate filenames automatically
      dup_count = 0
      while archived_file_names.include?(filename)
        dup_count += 1
        extname = File.extname(attachment.filename)
        basename = File.basename(attachment.filename, extname)
        filename = "#{basename}(#{dup_count})#{extname}"
      end
      zos.put_next_entry(filename)
      zos << IO.binread(attachment.diskfile)
      archived_file_names << filename
    end
  end
  buffer.string
ensure
  buffer&.close
end
```

#### Advantages of Core Approach

1. **Memory Efficient**: Uses in-memory buffer instead of temporary files
2. **Automatic Cleanup**: Proper resource management with ensure block
3. **Duplicate Handling**: Automatically handles duplicate filenames
4. **Security**: Built-in checks for readable attachments
5. **Unicode Support**: Proper handling of international filenames
6. **Error Handling**: Robust error handling and cleanup
7. **No File System Dependencies**: Works entirely in memory

## Combined Implementation Strategy

### Packet Creation Workflow

1. **Generate PDF**: Use `issue_to_pdf` to create issue PDF
2. **Archive Attachments**: Use `Attachment.archive_attachments` for attachment zip
3. **Combine**: Create final packet zip containing both PDF and attachments
4. **Deliver**: Use `send_data` for efficient download

### Proposed Controller Implementation

```ruby
class PacketCreationController < ApplicationController
  include Redmine::Export::PDF::IssuesPdfHelper
  before_action :find_issue
  before_action :authorize
  
  def create
    begin
      # Generate PDF using Redmine infrastructure
      pdf_content = issue_to_pdf(@issue, {journals: @issue.journals})
      
      # Create packet zip combining PDF and attachments
      packet_zip = create_packet_zip(pdf_content, @issue.attachments)
      
      send_data packet_zip,
                filename: "packet_#{@issue.id}.zip",
                type: 'application/zip',
                disposition: 'attachment'
    rescue => e
      logger.error "Packet creation failed for issue #{@issue.id}: #{e.message}"
      flash[:error] = "Error creating packet: #{e.message}"
      redirect_to issue_path(@issue)
    end
  end
  
  private
  
  def create_packet_zip(pdf_content, attachments)
    Zip::OutputStream.write_buffer do |zos|
      # Add PDF as first entry
      zos.put_next_entry("ticket_#{@issue.id}.pdf")
      zos << pdf_content
      
      # Add attachments with duplicate name handling
      archived_filenames = ["ticket_#{@issue.id}.pdf"]
      attachments.each do |attachment|
        next unless attachment.readable?
        
        filename = ensure_unique_filename(attachment.filename, archived_filenames)
        archived_filenames << filename
        
        zos.put_next_entry(filename)
        zos << IO.binread(attachment.diskfile)
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
```

## Technical Benefits

### Leveraging Existing Infrastructure

1. **PDF Generation**: 
   - No need to implement PDF rendering
   - Automatic handling of custom fields, formatting, internationalization
   - Consistent with Redmine's existing PDF exports

2. **Zip Creation**:
   - No temporary file management
   - Built-in error handling and resource cleanup
   - Proper handling of edge cases (duplicate names, unreadable files)

3. **Maintenance**:
   - Code automatically benefits from Redmine core improvements
   - No custom PDF/zip libraries to maintain
   - Reduced plugin complexity

### Performance Considerations

1. **Memory Usage**: In-memory zip creation avoids file system I/O
2. **Resource Management**: Automatic cleanup prevents resource leaks
3. **Error Handling**: Robust error handling prevents server issues
4. **Security**: Leverages Redmine's existing security checks

## Dependencies

### Required Gems
- **rubyzip**: Already included in Redmine core
- **ITCPDF**: Redmine's PDF library, already available

### Redmine Requirements
- **Version**: 5.0.0+ (as specified in plugin requirements)
- **Modules**: Core attachment and PDF export functionality

## Security Considerations

1. **Permission Checks**: Ensure user can view issue and attachments
2. **File Access**: Use Redmine's attachment security model
3. **Resource Limits**: Consider implementing size limits for large packets
4. **Error Disclosure**: Avoid exposing system paths in error messages

## Future Enhancements

1. **Batch Processing**: Could extend to create packets for multiple issues
2. **Custom Templates**: Could allow customization of PDF content
3. **Compression Options**: Could provide different compression levels
4. **Progress Feedback**: For large packets, could provide progress updates

## Conclusion

By leveraging Redmine's existing PDF and zip infrastructure, the BACHelp packet creation plugin can:
- Minimize code complexity and maintenance burden
- Ensure compatibility with Redmine core updates
- Provide robust, well-tested functionality
- Maintain consistency with Redmine's existing features
- Focus development effort on the specific packet creation workflow rather than reimplementing core functionality