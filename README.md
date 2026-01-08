# NY Senate Audit Utils Plugin

A comprehensive Redmine plugin providing audit utilities, employee data integration, and security workflow tools for the New York State Senate.

## Quick Start

### Installation

1. Clone plugin to `plugins/nysenate_audit_utils` directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone git@github.com:nysenate/redmine-plugin-nysenate-audit-utils.git nysenate_audit_utils
   ```

2. Run plugin migrations:
   ```bash
   bundle exec rake redmine:plugins:migrate NAME=nysenate_audit_utils RAILS_ENV=production
   ```

3. Restart Redmine

4. Configure the plugin in the UI:

   **Administration → Plugins → NY Senate Audit Utils → Configure**

### Requirements

- Redmine 5.0.0 or higher
- Ruby 2.7 or higher
- Access to ESS API (for employee integration features)

## Configuration

### 1. ESS Integration Settings

Configure access to the Employee Self Service API:

- **ESS Base URL**: Base URL for the ESS API endpoint
- **ESS API Key**: Authentication key for ESS API access

### 2. Custom Field Configuration

The plugin uses custom fields to store employee and request data.

Ensure that the following fields exist and are included in desired projects/trackers:

**Employee Fields:**
- `Employee ID` - Integer
- `Employee Name` - Text
- `Employee Email` - Text
- `Employee Phone` - Text
- `Employee Status` - List (Active/Inactive)
- `Employee UID` - Text
- `Employee Office` - Text

**Request Fields:**
- `Account Action` - List
- `Target System` - List

Configure field mappings via **Administration → Plugins → Configure**.

#### Auto-Configuration (Recommended)

Click **"Auto-Configure All Fields"** to automatically detect fields by name.


#### Manual Configuration

If auto-detection fails, manually select field IDs from dropdowns in plugin settings.

#### Validation

After configuration, check status indicators to ensure all required fields are mapped. The system shows:
- ✓ Configured fields with field names
- ✗ Missing fields with configuration prompts

### 3. Project Modules

Enable features per-project:

1. Go to **Projects → \*your project name\* → Settings** and scroll to the **Modules** section.
2. Enable desired modules:
   - **Audit Reporting** - Access to daily/weekly/monthly/triennial reports
   - **Employee Autofill** - Employee search and autofill functionality
   - **Packet Creation** - Create ticket packets containing ticket pdf + all issue attachments

### 4. Permissions

Configure role permissions under **Administration → Roles and Permissions**:

Edit the desired role(s) so that they grant the following permissions:

**Audit Utils Employee Autofill:**
- Use employee autofill

**Audit Utils Packet Creation:**
- Create ticket packets

**Audit Utils Reporting:**
- View audit reports
- Export audit reports

Assign the role(s) to the applicable user(s) in project member settings:  **Projects → \*your project name\* → Settings → Members**

## Features

### Reporting

Access via project menu: **Reports → Audit Utils**

- **Daily Reports**: Account status of employees with status changes in past 24 hours
- **Weekly Reports**: All completed tickets for previous week 
- **Monthly Reports**: Snapshot of current employee account status

### Ticket Packet Creation

Generate audit-ready zip packages containing:
- Ticket PDF with all details
- All file attachments

**Access:**
- **Single ticket**: "Create Packet" button on issue detail page
- **Bulk creation**: Right-click context menu on issue list (select multiple issues)

### Employee Autofill

- Real-time employee search widget on issue pages
- Automatic population of configured custom fields from ESS data
- AJAX-based search interface

### Request Code Mapping

Automatic request type classification based on Account Action and Target System combinations.

### ESS Integration

Library providing:
- Employee search and retrieval via ESS REST API
- Employee Status change tracking (appointments, terminations, transfers, etc.)
