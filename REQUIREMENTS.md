# BACHelp Packet Creation Plugin - Requirements

## Overview

This plugin enables the creation of "packets" for Redmine tickets, which are comprehensive bundles containing all information related to a specific ticket. These packets are primarily used during auditing processes to provide auditors with complete ticket documentation.

## Functional Requirements

### 1. Packet Creation Button - UPDATED DURING DEVELOPMENT
- ~~Add a "Create Packet" button to the ticket view page~~ **CHANGED**: Button integrated into attachment contextual menu
- Button should be visible to users with appropriate permissions ✓
- ~~Button should be contextually placed near other ticket actions~~ **CHANGED**: Button placed in attachment contextual menu alongside edit/download icons

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

### 3. Permissions - SIMPLIFIED DURING DEVELOPMENT
- ~~Only allow packet creation for tickets user can view~~ **UPDATED**: Packet creation available to users who can view attachments
- **CHANGED**: Removed custom `create_packet` permission in favor of using existing attachment viewing permissions

### 4. Performance
- Handle tickets with many attachments efficiently
- Implement reasonable timeouts for large packet creation
- Consider memory usage for large files
- Provide feedback for long-running operations

## User Interface Requirements

### 1. Button Placement - UPDATED DURING DEVELOPMENT
- ~~Add button to issue view page~~ **CHANGED**: Button integrated into attachment contextual menu
- ~~Position near other ticket actions (Edit, Copy, etc.)~~ **CHANGED**: Button placed in attachment contextual menu alongside edit/download icons
- Use consistent styling with Redmine theme ✓
- Include appropriate icon ✓ (uses 'package' sprite icon)

### 2. Error Handling
- Display clear error messages for failures
- Handle missing attachments gracefully
- Provide feedback for permission issues
- Log errors for debugging

## Security Requirements

### 1. Access Control - SIMPLIFIED DURING DEVELOPMENT
- Verify user permissions before packet creation ✓
- Ensure user can access all included attachments ✓
- Respect project-level security settings ✓
- Prevent unauthorized packet downloads ✓
- **SIMPLIFIED**: Uses `attachments_visible?` check instead of custom permission system

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

### 1. Enhanced Content
- Option to include related tickets
- Support for project documentation
- Custom packet templates

### 2. Integration
- API endpoints for programmatic packet creation
- Integration with external audit systems
- Export to other formats beyond ZIP

## New Feature: Multi-issue Packet Creation ✅ COMPLETED

### 1. Overview ✅ IMPLEMENTED
Multi-issue packet creation functionality that allows users to create packets for multiple selected tickets simultaneously. This feature is accessible from the issues page via the existing issue context menu and has been fully implemented with comprehensive test coverage.

### 2. Functional Requirements ✅ COMPLETED

#### 2.1 User Interface Integration ✅ IMPLEMENTED
- ✅ Added "Create Multi Packet" option to the issue context menu via `IssueContextMenuHook`
- ✅ Option only appears when multiple issues are selected (2 or more)
- ✅ Uses hook-based implementation pattern for integration with existing context menu
- ✅ Includes 'package' sprite icon for consistency

#### 2.2 Multi-issue Packet Content ✅ IMPLEMENTED
- ✅ Creates a single ZIP file containing individual packets for each selected issue
- ✅ **Naming convention**: `multi_packet_{timestamp}.zip` (e.g., `multi_packet_20250716_143022.zip`)
- ✅ **Internal structure** with nested packet directories:
  ```
  multi_packet_20240716_143022.zip
  ├── packet_123/
  │   ├── ticket_123.pdf
  │   ├── attachment_1.pdf
  │   └── attachment_2.jpg
  ├── packet_124/
  │   ├── ticket_124.pdf
  │   └── attachment_3.doc
  └── packet_125/
      ├── ticket_125.pdf
      ├── attachment_4.pdf
      └── attachment_5.png
  ```

#### 2.3 Permission Handling ✅ IMPLEMENTED
- ✅ Only processes issues the user can view via `user.allowed_to?(:view_issues, issue.project)` checks
- ✅ Fails entire operation if user cannot view any selected issue or its attachments
- ✅ Uses existing `attachments_visible?` permission checks in controller authorization
- ✅ Provides clear error messages for permission failures

#### 2.4 Download Behavior ✅ IMPLEMENTED
- ✅ Triggers immediate download of multi-issue packet ZIP file
- ✅ Fail-fast approach: if any issue fails, entire operation fails
- ✅ Handles timeout scenarios gracefully with proper error handling
- ✅ Provides clear success/failure messages via flash notifications

### 3. Technical Requirements ✅ COMPLETED

#### 3.1 Error Handling ✅ IMPLEMENTED
- ✅ Stops processing and fails entire operation if any individual packet creation fails
- ✅ Provides detailed error messages indicating which issue caused the failure
- ✅ Logs errors for debugging purposes via Rails.logger
- ✅ Gracefully handles missing attachments or corrupted files

#### 3.2 Implementation Approach ✅ COMPLETED
- ✅ Extended existing `PacketCreationController` with `create_multi_packet` action
- ✅ Added new route `/issues/create_multi_packet` for multi-issue packet creation
- ✅ Leverages existing packet creation logic via `PacketCreationService` module
- ✅ Uses fail-fast pattern throughout the process in both service and controller layers

### 4. User Experience Requirements ✅ COMPLETED

#### 4.1 Context Menu Integration ✅ IMPLEMENTED
- ✅ Menu item only appears when user has sufficient permissions for all selected issues
- ✅ Shows appropriate feedback (no menu item) when no issues selected or insufficient permissions
- ✅ Uses consistent styling with existing context menu items (icon, link styling)
- ✅ Only shows option when multiple issues are selected (2 or more)

#### 4.2 Feedback ✅ IMPLEMENTED
- ✅ Browser handles loading indicator during multi-issue packet creation download
- ✅ Displays clear success/failure messages via flash notifications
- ✅ Includes specific error details for failures in both logs and user-facing messages

### 5. Security Requirements ✅ COMPLETED

#### 5.1 Access Control ✅ IMPLEMENTED
- ✅ Verifies user permissions for each selected issue individually
- ✅ Respects project-level security settings via Redmine's permission system
- ✅ Prevents unauthorized access to issue data or attachments
- ✅ Validates issue IDs and handles missing/invalid IDs gracefully
- ✅ Uses existing Redmine security mechanisms (`allowed_to?`, `visible?`, `attachments_visible?`)

## Implementation Summary ✅ COMPLETED

The multi-issue packet creation feature has been successfully implemented with the following components:

### Files Added/Modified:
- **NEW**: `lib/issue_context_menu_hook.rb` - Hook for context menu integration
- **NEW**: `lib/multi_packet_creation_service.rb` - Service for creating multi-issue packets
- **MODIFIED**: `app/controllers/packet_creation_controller.rb` - Added `create_multi_packet` action
- **MODIFIED**: `config/routes.rb` - Added multi-issue route
- **MODIFIED**: `config/locales/en.yml` - Added multi-packet localization strings
- **MODIFIED**: `init.rb` - Loaded new components

### Test Coverage:
- **NEW**: `test/unit/multi_packet_creation_service_test.rb` - Service tests
- **NEW**: `test/functional/packet_creation_controller_multi_test.rb` - Controller tests  
- **NEW**: `test/unit/issue_context_menu_hook_test.rb` - Hook tests

### Key Features:
- **Context Menu Integration**: Appears only for multiple selected issues
- **Nested ZIP Structure**: Individual packet folders within main ZIP
- **Fail-Fast Error Handling**: Operation fails if any single issue fails
- **Comprehensive Permission Validation**: Respects all Redmine security settings
- **Full Test Coverage**: 31 tests passing with 119 assertions

### Usage:
1. Navigate to issues list page
2. Select multiple issues using checkboxes
3. Right-click to open context menu
4. Click "Create Multi Packet" option
5. Download begins immediately with filename format: `multi_packet_YYYYMMDD_HHMMSS.zip`