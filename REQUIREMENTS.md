# BACHelp Packet Creation Plugin - Requirements

## Overview

This plugin enables the creation of "packets" for Redmine tickets, which are comprehensive bundles containing all information related to a specific ticket. These packets are primarily used during auditing processes to provide auditors with complete ticket documentation.

## Functional Requirements

### 1. Packet Creation Button
- Add a "Create Packet" button to the ticket view page
- Button should be visible to users with appropriate permissions
- Button should be contextually placed near other ticket actions

### 2. Packet Content
A packet must include:
- **PDF view of the ticket**: Complete ticket information rendered as PDF
  - Ideally same as the PDF rendered by `lib/redmine/export/pdf/issues_pdf_helper.rb`
  - All ticket fields and custom fields
  - Ticket history/journal entries
  - Comments and notes
  - Status transitions
  - Time entries (if any)
- **All ticket attachments**: Original files attached to the ticket
  - Preserve original filenames
  - Maintain file integrity

### 3. Packet Format
- **Output format**: ZIP file
- **Naming convention**: `packet_{ticket_id}.zip`
- **Internal structure**:
  ```
  packet_123.zip
  ├── ticket_123.pdf
  ├── attachment_1.pdf
  ├── attachment_2.jpg
  └── attachment_n.doc
  ```

### 4. Download Behavior
- Clicking "Create Packet" should trigger immediate download
- No intermediate pages or confirmation dialogs
- Handle large files gracefully
- Provide appropriate error messages if packet creation fails

## Technical Requirements

### 1. PDF Generation
- Ideally would be able to leverage the existing Redmine code to do this. From Redmine root: `lib/redmine/export/pdf/issues_pdf_helper.rb`
  - The default redmine ticket pdf would satisfy these requirements
- Generate high-quality PDF representation of ticket
- Include all visible ticket information
- Maintain readable formatting and layout
- Handle custom fields properly
- Include ticket history in chronological order

### 2. File Handling
- Support all attachment file types that Redmine supports
- Handle large attachments efficiently
- Preserve original file metadata where possible
- Handle cases where attachments may be missing or corrupted

### 3. Permissions
- Create new permission: `create_packet`
- Integrate with Redmine's existing permission system
- Respect project-level permissions
- Only allow packet creation for tickets user can view

### 4. Performance
- Handle tickets with many attachments efficiently
- Implement reasonable timeouts for large packet creation
- Consider memory usage for large files
- Provide feedback for long-running operations

## User Interface Requirements

### 1. Button Placement
- Add button to issue view page
- Position near other ticket actions (Edit, Copy, etc.)
- Use consistent styling with Redmine theme
- Include appropriate icon

### 2. Error Handling
- Display clear error messages for failures
- Handle missing attachments gracefully
- Provide feedback for permission issues
- Log errors for debugging

## Security Requirements

### 1. Access Control
- Verify user permissions before packet creation
- Ensure user can access all included attachments
- Respect project-level security settings
- Prevent unauthorized packet downloads

### 2. File Security
- Validate attachment file paths
- Prevent directory traversal attacks
- Sanitize filenames in ZIP structure
- Handle malicious file types appropriately

## Compatibility Requirements

### 1. Redmine Version
- Support Redmine 5.0.0 and higher
- Maintain compatibility with standard Redmine installations
- Work with common Redmine configurations

### 3. Browsers
- Support all browsers that Redmine supports
- Handle download triggers consistently
- Provide appropriate MIME types

## Future Considerations

### 1. Batch Operations
- Consider adding bulk packet creation for multiple tickets
- Support for project-wide packet generation
- Scheduled packet creation for reporting

### 2. Enhanced Content
- Option to include related tickets
- Support for project documentation
- Custom packet templates

### 3. Integration
- API endpoints for programmatic packet creation
- Integration with external audit systems
- Export to other formats beyond ZIP