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

### Zip Creation Implementation - FINAL APPROACH USED

**Decision Made During Development:**
Instead of using Redmine's `Attachment.archive_attachments`, we implemented a custom solution that combines PDF and attachments in a single zip file.

**Implemented Approach:**
```ruby
class PacketCreationService
  def create_packet_with_pdf(pdf_content)
    create_combined_zip(pdf_content, @issue.attachments)
  end

  private

  def create_combined_zip(pdf_content, attachments)
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
          Rails.logger.warn "Failed to add attachment: #{e.message}"
          # Continue with other attachments
        end
      end
    end.string
  end
end
```

**Key Benefits of Final Implementation:**
1. **Combined PDF + Attachments**: Creates unified packet with both PDF and attachments
2. **Memory Efficient**: Uses in-memory buffer, no temporary files
3. **Robust Error Handling**: Individual attachment failures don't break entire packet
4. **Duplicate Handling**: Automatic filename conflict resolution
5. **Service Pattern**: Clean separation of concerns

## Final Implementation Strategy - AS IMPLEMENTED

### Packet Creation Workflow

1. **Generate PDF**: Use `issue_to_pdf` to create issue PDF in controller context ✓
2. ~~**Archive Attachments**: Use `Attachment.archive_attachments` for attachment zip~~ **CHANGED**: Custom zip creation for combined PDF+attachments
3. **Combine**: Create final packet zip containing both PDF and attachments ✓
4. **Deliver**: Use `send_data` for efficient download ✓

### UI Integration Changes

**Original Plan**: Add button to issue view page near other actions

**Final Implementation**: 
- Button integrated into attachment contextual menu
- Uses AttachmentsHelper patch to modify existing attachment display
- Server-side HTML modification with Nokogiri
- Consistent styling with existing contextual menu buttons

### Actual Controller Implementation - UPDATED DURING DEVELOPMENT

**Key Changes from Original Plan:**
- Added extensive ActionView helper includes for PDF generation context
- Moved PDF generation logic to controller for proper helper access
- Delegated zip creation to separate service class
- Enhanced error handling and logging
- Simplified permission system to use attachment visibility checks

```ruby
class PacketCreationController < ApplicationController
  include Redmine::Export::PDF::IssuesPdfHelper
  include CustomFieldsHelper
  include IssuesHelper
  include ApplicationHelper
  # ... additional helper includes for PDF generation context
  
  before_action :find_issue
  before_action :authorize_packet_creation  # CHANGED: different authorization method
  
  def create
    begin
      # Generate PDF directly in controller with proper helper context
      @journals = @issue.journals.visible.preload(:user, :details)
      pdf_content = issue_to_pdf(@issue, journals: @journals)
      
      # Use service for zip creation
      packet_zip = PacketCreationService.create_packet(@issue, pdf_content)
      
      send_data packet_zip,
                filename: "packet_#{@issue.id}.zip",
                type: 'application/zip',
                disposition: 'attachment'
    rescue => e
      # Enhanced error handling with proper logging
      Rails.logger.error "Packet creation failed for issue #{@issue.id}: #{e.message}"
      flash[:error] = l(:error_packet_creation_failed)  # Internationalized error
      redirect_to issue_path(@issue)
    end
  end
  
  private
  
  def authorize_packet_creation
    # SIMPLIFIED: Use attachment visibility instead of custom permissions
    unless @issue.attachments_visible?(User.current)
      flash[:error] = l(:notice_not_authorized)
      redirect_to issue_path(@issue)
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

## Security Considerations - IMPLEMENTED

1. **Permission Checks**: Ensure user can view issue and attachments ✓
   - **IMPLEMENTED**: Uses `attachments_visible?` check
   - **SIMPLIFIED**: Removed custom permission system
2. **File Access**: Use Redmine's attachment security model ✓
   - **IMPLEMENTED**: Leverages attachment `readable?` method
3. **Resource Limits**: Consider implementing size limits for large packets ⚠️
   - **NOT IMPLEMENTED**: No size limits in current version
4. **Error Disclosure**: Avoid exposing system paths in error messages ✓
   - **IMPLEMENTED**: Internationalized error messages, safe logging

## Multi-issue Packet Creation Implementation

### Context Menu Integration

Based on research into the existing issue context menu (`app/views/context_menus/issues.html.erb`) and the current AttachmentsHelper patch implementation, we can extend the plugin to support multi-issue packet creation.

#### Issue Context Menu Integration Approach

For multi-issue packet creation, we'll use a hook-based approach since the issue context menu is a separate view template. The pattern from the existing context menu shows:

1. **Hook-based Integration**: Use `call_hook(:view_issues_context_menu_end, ...)` pattern
2. **Conditional Display**: Show only when multiple issues are selected
3. **Permission Checks**: Verify user can view all selected issues and attachments
4. **Consistent Styling**: Use same patterns as existing context menu items

#### Implementation Strategy

**Primary Approach: Hook-based Integration**
```ruby
# lib/issue_context_menu_hook.rb
class IssueContextMenuHook < Redmine::Hook::ViewListener
  def view_issues_context_menu_end(context = {})
    issues = context[:issues] || []
    can = context[:can] || {}
    
    # Only show for multiple issues
    return '' if issues.length <= 1
    
    # Check permissions for all issues
    return '' unless issues.all? { |issue| 
      issue.visible?(User.current) && issue.attachments_visible?(User.current)
    }
    
    content_tag :li do
      context_menu_link(
        sprite_icon('package', l(:button_create_multi_packet)),
        create_multi_packet_issues_path(:ids => issues.map(&:id)),
        method: :post,
        class: 'icon icon-package',
        title: l(:button_create_multi_packet_title)
      )
    end
  end
end
```

**Alternative: View Template Patch**
If the hook approach proves insufficient, we could monkey patch the context menu template directly using a similar Nokogiri-based approach as used for the attachments menu.

### Technical Implementation Requirements

#### Controller Extension
```ruby
class PacketCreationController < ApplicationController
  def create_multi_packet
    issue_ids = params[:ids].map(&:to_i)
    @issues = Issue.where(id: issue_ids).visible(User.current)
    
    # Fail-fast: ensure all issues are accessible
    unless @issues.count == issue_ids.count
      flash[:error] = l(:error_unauthorized_issues)
      redirect_back_or_default(home_path)
      return
    end
    
    # Verify attachment permissions for all issues
    unless @issues.all? { |issue| issue.attachments_visible?(User.current) }
      flash[:error] = l(:error_unauthorized_attachments)
      redirect_back_or_default(home_path)
      return
    end
    
    begin
      packet_zip = PacketCreationService.create_multi_packet(@issues, pdf_contents_by_issue_id)
      
      send_data packet_zip,
                filename: "multi_packet_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip",
                type: 'application/zip',
                disposition: 'attachment'
    rescue => e
      Rails.logger.error "Multi-packet creation failed: #{e.message}"
      flash[:error] = l(:error_multi_packet_creation_failed)
      redirect_back_or_default(home_path)
    end
  end
end
```

#### Service Class for Multi-issue Processing
```ruby
module PacketCreationService
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
end
```

#### Routing
```ruby
# config/routes.rb
post 'issues/create_multi_packet', to: 'packet_creation#create_multi_packet'
```

### Key Implementation Challenges

1. **PDF Generation Context**: Multi-issue PDF generation requires proper controller/helper context for each issue
2. **Memory Management**: Large multi-issue packets could consume significant memory
3. **Error Handling**: Fail-fast approach requires careful error propagation
4. **Permission Validation**: Must verify permissions for each issue individually

### Future Enhancements

1. **Custom Templates**: Could allow customization of PDF content
2. **Compression Options**: Could provide different compression levels
3. **Progress Feedback**: For large packets, could provide progress updates
4. **Scheduling**: Could support background processing for very large multi-issue packets

## Conclusion

By leveraging Redmine's existing PDF and zip infrastructure, the BACHelp packet creation plugin can:
- Minimize code complexity and maintenance burden
- Ensure compatibility with Redmine core updates
- Provide robust, well-tested functionality
- Maintain consistency with Redmine's existing features
- Focus development effort on the specific packet creation workflow rather than reimplementing core functionality