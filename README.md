# NY Senate Audit Utils Plugin

A comprehensive Redmine plugin providing audit utilities, user data integration, and security workflow tools for the New York State Senate.

## Quick Start

### Installation

*Note: Prefix `rake` commands with `bundle exec` if using Bundler*

1. Clone plugin to `plugins/nysenate_audit_utils` directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone git@github.com:nysenate/redmine-plugin-nysenate-audit-utils.git nysenate_audit_utils
   ```
   
1. Install plugin dependencies:
      ```bash
      # If using bundler
      bundle install
      ```
      or
      ```bash
      # If not using bundler
      gem install webmock
      ```

1. Run plugin migrations (from Redmine root):
   ```bash
   cd /path/to/redmine
   rake redmine:plugins:migrate NAME=nysenate_audit_utils RAILS_ENV=production
   ```

1. (Optional) Run tests to verify installation (from Redmine root):
   ```bash
   rake redmine:plugins:test NAME=nysenate_audit_utils
   ```

1. Restart Redmine

1. Configure the plugin in the UI:

   **Administration → Plugins → NY Senate Audit Utils → Configure**

### Requirements

- Redmine 6.0 or higher
- Ruby 3.1 or higher
- Access to ESS API (for employee integration features)

## Configuration

### 1. ESS Integration Settings

Configure access to the Employee Self Service API:

- **ESS Base URL**: Base URL for the ESS API endpoint
- **ESS API Key**: Authentication key for ESS API access

### 2. Custom Field Configuration

The plugin uses custom fields to store user and request data.

Ensure that the following fields exist and are included in desired projects/trackers:

**User Fields:**
- `User Type` - List (Employee/Vendor)
- `User ID` - Integer
- `User Name` - Text
- `User Email` - Text
- `User Phone` - Text
- `User Status` - List (Active/Inactive)
- `User UID` - Text
- `User Location` - Text

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
   - **User Autofill** - User search and autofill functionality (employees, vendors, etc.)
   - **Packet Creation** - Create ticket packets containing ticket pdf + all issue attachments

### 4. Permissions

Configure role permissions under **Administration → Roles and Permissions**:

Edit the desired role(s) so that they grant the following permissions:

**Audit Utils User Autofill:**
- Use user autofill

**Audit Utils Packet Creation:**
- Create ticket packets

**Audit Utils Reporting:**
- View audit reports
- Export audit reports

Assign the role(s) to the applicable user(s) in project member settings:  **Projects → \*your project name\* → Settings → Members**

### 5. Email Reporting Configuration (Optional)

Configure default recipients for automated email delivery of audit reports:

1. Go to **Administration → Plugins → NY Senate Audit Utils → Configure**
2. Scroll to the **Email Reporting Configuration** section
3. Enter **Default Report Recipients**: Comma-separated email addresses for all automated reports

**Note**: This sets the default recipient list used by all report rake tasks. Individual rake tasks can override this by providing a `recipients` parameter. Scheduled reports must be configured using cron jobs (see [Scheduled Email Reports](#scheduled-email-reports) below).

## Features

### Reporting

Access via project menu: **Reports → Audit Utils**

- **Daily Reports**: Account status of employees with status changes in past 24 hours
- **Weekly Reports**: All completed tickets for previous week
- **Monthly Reports**: Snapshot of current employee account status

All reports support CSV export for further analysis.

#### Scheduled Email Reports

Reports can be automatically generated and emailed on a schedule using rake tasks and cron jobs:

- **Daily Reports**: Employee status changes with account information
- **Weekly Reports**: All active tickets for the current week
- **Monthly Reports**: Current or historical account status snapshots

Each report is delivered as an email with the full data attached as a CSV file.

See [Rake Tasks](#rake-tasks) section below for setup instructions.

### Ticket Packet Creation

Generate audit-ready zip packages containing:
- Ticket PDF with all details
- All file attachments

**Access:**
- **Single ticket**: "Create Packet" button on issue detail page
- **Bulk creation**: Right-click context menu on issue list (select multiple issues)

### Tracked User Management

Manage non-employee tracked users (vendors, contractors, etc.) through the admin interface:

**Access:** **Administration → Manage Tracked Users** (admin-only)

**Features:**
- Create, edit, and delete vendor records
- Auto-generated vendor IDs (V1, V2, V3, etc.)
- Search and filter tracked user list
- Manage tracked user details: name, email, phone, location, status

**Note:** Employee data is read-only from the ESS API and cannot be modified locally.

### User Autofill

- Real-time user search widget on issue pages with type selection (Employee, Vendor)
- Employee data sourced from ESS API; vendor data managed locally
- Automatic population of configured custom fields
- AJAX-based search interface

### Request Code Mapping

Automatic request type classification based on Account Action and Target System combinations.

### ESS Integration

Library providing:
- Employee search and retrieval via ESS REST API
- Employee Status change tracking (appointments, terminations, transfers, etc.)

## Rake Tasks

The plugin provides rake tasks for generating and emailing audit reports on a schedule.

**Important**: All rake tasks must be run from the Redmine root directory.

### Available Tasks

#### Send Daily Report

Generates and emails the daily report showing employees with status changes.

```bash
# Uses configured default recipients
bundle exec rake nysenate_audit_utils:send_daily_report RAILS_ENV=production

# Override recipients
bundle exec rake nysenate_audit_utils:send_daily_report recipients="email1@example.com,email2@example.com" RAILS_ENV=production
```

**Options:**
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `start_date` (optional): Start date in YYYY-MM-DD format (defaults to business day calculation)
- `end_date` (optional): End date in YYYY-MM-DD format (defaults to now)

**Example with date range:**
```bash
bundle exec rake nysenate_audit_utils:send_daily_report \
  start_date="2026-03-01" \
  end_date="2026-03-02" \
  RAILS_ENV=production
```

#### Send Weekly Report

Generates and emails the weekly report showing all active tickets for the current week.

```bash
# Uses configured default recipients
bundle exec rake nysenate_audit_utils:send_weekly_report RAILS_ENV=production

# Override recipients
bundle exec rake nysenate_audit_utils:send_weekly_report recipients="email1@example.com,email2@example.com" RAILS_ENV=production
```

**Options:**
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)

#### Send Monthly Report

Generates and emails the monthly report showing account statuses for a target system.

```bash
# Uses configured default recipients
bundle exec rake nysenate_audit_utils:send_monthly_report target_system="Oracle / SFMS" RAILS_ENV=production

# Override recipients
bundle exec rake nysenate_audit_utils:send_monthly_report \
  target_system="AIX" \
  recipients="email1@example.com,email2@example.com" \
  RAILS_ENV=production
```

**Options:**
- `target_system` (required): Target system name (e.g., "Oracle / SFMS", "AIX", "SFS")
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `mode` (optional): Report mode - "current" or "monthly" (default: "current")
- `month` (optional): Month number 1-12 (for monthly mode, default: current month)
- `year` (optional): Year (for monthly mode, default: current year)

**Example - Historical Snapshot:**
```bash
bundle exec rake nysenate_audit_utils:send_monthly_report \
  target_system="AIX" \
  mode=monthly \
  month=1 \
  year=2026 \
  RAILS_ENV=production
```

### Setting Up Scheduled Reports with Cron

To automate report delivery, create wrapper scripts and configure cron jobs.

#### Step 1: Create Wrapper Scripts

Create a directory for your scripts (e.g., `/path/to/redmine/scripts/`):

```bash
mkdir -p /path/to/redmine/scripts
```

Create wrapper scripts for each report type:

**Daily Report Script** (`scripts/send_daily_audit_report.sh`):
```bash
#!/bin/bash
cd /path/to/redmine
bundle exec rake nysenate_audit_utils:send_daily_report RAILS_ENV=production
```

**Weekly Report Script** (`scripts/send_weekly_audit_report.sh`):
```bash
#!/bin/bash
cd /path/to/redmine
bundle exec rake nysenate_audit_utils:send_weekly_report RAILS_ENV=production
```

**Monthly Report Script - Oracle/SFMS** (`scripts/send_monthly_oracle_report.sh`):
```bash
#!/bin/bash
cd /path/to/redmine
bundle exec rake nysenate_audit_utils:send_monthly_report \
  target_system="Oracle / SFMS" \
  RAILS_ENV=production
```

**Monthly Report Script - AIX** (`scripts/send_monthly_aix_report.sh`):
```bash
#!/bin/bash
cd /path/to/redmine
bundle exec rake nysenate_audit_utils:send_monthly_report \
  target_system="AIX" \
  RAILS_ENV=production
```

Make the scripts executable:
```bash
chmod +x /path/to/redmine/scripts/send_*_audit_report.sh
```

#### Step 2: Configure Cron Jobs

Edit your crontab:
```bash
crontab -e
```

Add entries for your desired schedule:

```cron
# Daily audit report at 8:00 AM on weekdays
0 8 * * 1-5 /path/to/redmine/scripts/send_daily_audit_report.sh >> /var/log/redmine/audit_reports.log 2>&1

# Weekly audit report at 9:00 AM every Monday
0 9 * * 1 /path/to/redmine/scripts/send_weekly_audit_report.sh >> /var/log/redmine/audit_reports.log 2>&1

# Monthly Oracle/SFMS report at 10:00 AM on the 1st of each month
0 10 1 * * /path/to/redmine/scripts/send_monthly_oracle_report.sh >> /var/log/redmine/audit_reports.log 2>&1

# Monthly AIX report at 10:15 AM on the 1st of each month
15 10 1 * * /path/to/redmine/scripts/send_monthly_aix_report.sh >> /var/log/redmine/audit_reports.log 2>&1
```

**Cron Schedule Examples:**
- `0 8 * * 1-5` - 8:00 AM Monday through Friday
- `0 9 * * 1` - 9:00 AM every Monday
- `0 10 1 * *` - 10:00 AM on the 1st day of every month
- `0 7 * * *` - 7:00 AM every day

#### Step 3: Verify Setup

Test your scripts manually before relying on cron:
```bash
/path/to/redmine/scripts/send_daily_audit_report.sh
```

Check the log file for any errors:
```bash
tail -f /var/log/redmine/audit_reports.log
```

### Email Configuration

**Important**: Ensure Redmine's email delivery is properly configured in `config/configuration.yml` before using these rake tasks.

Example SMTP configuration:
```yaml
production:
  email_delivery:
    delivery_method: :smtp
    smtp_settings:
      address: smtp.example.com
      port: 587
      domain: example.com
      authentication: :plain
      user_name: "redmine@example.com"
      password: "your_password"
```

Test email delivery with Redmine's built-in test:
```bash
bundle exec rake redmine:email:test[admin_login] RAILS_ENV=production
```
