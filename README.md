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
- `User Type` - List (Employee/Vendor/Volunteer)
- `User ID` - Integer
- `User Name` - Text
- `User Email` - Text
- `User Phone` - Text
- `User Status` - List (Active/Inactive)
- `User UID` - Text
- `User Office` - Text

**Request Fields:**
- `Account Action` - List
- `Target System` - List

**Reporting Fields:**
- `BAC #` - Text — legacy BAC system ticket number shown on the Quarterly/Annual report; the field value may be left blank once the legacy system is phased out, but the field mapping must be configured.

Configure field mappings via **Administration → Plugins → Configure**.

#### Auto-Configuration (Recommended)

Click **"Auto-Configure All Fields"** to automatically detect fields by name.


#### Manual Configuration

If auto-detection fails, manually select field IDs from dropdowns in plugin settings.

#### Validation

After configuration, check status indicators to ensure all required fields are mapped. The system shows:
- ✓ Configured fields with field names
- ✗ Missing fields with configuration prompts

### 3. Project Module

Enable the Audit Utils module per-project:

1. Go to **Projects → \*your project name\* → Settings** and scroll to the **Modules** section.
2. Enable the **Audit Utils** module to activate all audit utilities features:
   - Daily/weekly/monthly report generation and viewing
   - User search and autofill functionality (employees, vendors, volunteers, etc.)
   - Ticket packet creation (PDF + attachments in zip format)
   - Tracked user management (vendors, volunteers, contractors, etc.)

### 4. Permissions

Configure role permissions under **Administration → Roles and Permissions**:

Edit the desired role(s) so that they grant the following permissions under **Audit Utils**:
- **View audit reports** - Access to daily/weekly/monthly reports
- **Export audit reports** - Export reports to CSV
- **Use user autofill** - User search and autofill functionality
- **Create ticket packets** - Generate ticket packets (PDF + attachments)
- **Manage Vendors/Volunteers** - Create/edit/delete vendor, volunteer, and contractor records

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

- **Daily Reports**: Account status of employees with status changes. Two modes:
  - **Last Business Day** (default): single date picker, defaults to today. Covers the previous business day at 00:00 → selected date at 00:00. If the selected date is a Monday, the range starts at the previous Friday at 00:00 so the prior weekend is included.
  - **Date Range**: explicit start/end date pickers (range runs 00:00 → 00:00).
  - Each row has a **Create Ticket** action (shown to users with permission to add issues) that opens a new ticket pre-filled with that account holder's information — the account holder fields are re-fetched live from ESS and the form is left unsaved for review. The ticket's tracker is auto-detected as the project tracker carrying the Account Holder custom fields. The daily report (CSV for the same date range) is seeded as a pending attachment, so it is saved with the ticket when you submit; remove it before saving if you don't want it.
- **Weekly Reports**: Closed tickets from the previous full week (Sunday–Sunday), ordered by close date
- **Quarterly / Annual Reports**: Closed tickets for a single target system, feeding the SFMS Quarterly Audit and the SFS Annual (Account & Roles Validation) Audit. A **System** selector switches between:
  - **SFMS** (Oracle/SFMS, request codes `USR*`): a dropdown of *offset* audit quarters (Nov 1–Jan 31, Feb 1–Apr 30, May 1–Jul 31, Aug 1–Oct 31), defaulting to the most recently completed quarter; an explicit start/end range overrides it.
  - **SFS** (request codes `SFS*`): pick an **end date**; the start auto-fills to one year prior (override allowed).

  CSV columns match the legacy audit spreadsheet for direct Access import: `RequestType, FullName, Userid, Office, EntryDate, CompletedDate, BacNumber, SenDevNumber, Description` (`SenDevNumber` is the Redmine ticket #; `BacNumber` comes from the **BAC #** custom field — see [Custom Field Configuration](#custom-field-configuration)). View-only/CSV download; no scheduled email.
- **Monthly Reports**: Account status snapshot; defaults to the last complete month, active accounts only
- **Account Holder Access Report**: Listing of all currently active account access across every target system — one row per account (account holder × system), ordered by account holder name. "Active" is determined the same way as the Monthly report (the latest closed Add/Delete ticket for that account holder + system). Columns: Account Holder Name, Account Holder Type, Account Holder Username, Target System, Request Code (the request code of the latest Add ticket). Supports a search filter (matches Account Holder Name or Username, with matches highlighted in the web view) and an Account Holder Type filter (All, Non-employee, Employee, Vendor, Volunteer); both filters apply to the CSV export as well. View-only with a CSV export; no scheduled email.

All on-screen reports are paginated using Redmine's standard pagination
control (page links and per-page selector, matching the issue list). Sorting
and filters are preserved across pages. CSV exports always contain the full,
unpaginated dataset for further analysis.

#### Scheduled Email Reports

Reports can be automatically generated and emailed on a schedule using rake tasks and cron jobs:

- **Daily Reports**: Employee status changes with account information
- **Weekly Reports**: Closed tickets from the previous full week
- **Monthly Reports**: Monthly or current account status snapshots
- **All-Systems Monthly Reports**: Monthly snapshot ZIP containing one CSV per target system

Each report is delivered as an email with the full data attached as a CSV file. See the [Rake Tasks](#rake-tasks) section for available tasks and options.

### Ticket Packet Creation

Generate audit-ready zip packages containing:
- Ticket PDF with all details
- All file attachments

**Access:**
- **Single ticket**: "Create Packet" button on issue detail page
- **Bulk creation**: Right-click context menu on issue list (select multiple issues)

### Tracked User Management

Manage non-employee tracked users (vendors, volunteers, contractors, etc.) through the admin interface:

**Access:** **Administration → Manage Vendors/Volunteers** (admin-only)

**Features:**
- Create, edit, and delete vendor records
- Auto-generated vendor IDs (V1, V2, V3, etc.)
- Search and filter tracked user list
- Manage tracked user details: name, email, phone, location, status

**Note:** Employee data is read-only from the ESS API and cannot be modified locally.

### User Autofill

- Real-time user search widget on issue pages with type selection (Employee, Vendor, Volunteer)
- Employee data sourced from ESS API; vendor and volunteer data managed locally
- Automatic population of configured custom fields
- AJAX-based search interface

### Request Code Mapping

Automatic request type classification based on Account Action and Target System combinations.

### ESS Integration

Library providing:
- Employee search and retrieval via ESS REST API
- Employee Status change tracking (appointments, terminations, transfers, etc.)

## Rake Tasks

The plugin provides rake tasks for generating and emailing audit reports. Run these on a cron schedule to automate report delivery (see your system's crontab documentation).

**Important**: All rake tasks must be run from the Redmine root directory.

Each successful rake run also archives a copy of the generated CSV/ZIP to the selected project's **Files** repository (with a timestamped filename) for audit trail. If the project does not have the Files module enabled, archiving is skipped with a warning and the email is still sent.

Every email-sending task accepts a `no_email` flag (`1`, `true`, or `yes`) that suppresses the email entirely. The report is still generated and archived to project Files, and `recipients` are not required in this mode. This is useful for generating/archiving a report without notifying anyone, or for testing.

### Available Tasks

#### Send Daily Report

Generates and emails the daily report showing employees with status changes.

```bash
# Default: Last Business Day mode for today (covers yesterday → today; Mondays cover Fri → Mon)
rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" RAILS_ENV=production

# Last Business Day mode for a specific date
rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" mode="business_day" end_date="2026-05-18" RAILS_ENV=production

# Explicit date range
rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" mode="range" start_date="2026-05-15" end_date="2026-05-17" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `mode` (optional): `business_day` (default) or `range`
  - `business_day`: uses `end_date` only (default today). Range = previous business day 00:00 → `end_date` 00:00. Monday `end_date` extends back to the previous Friday.
  - `range`: uses `start_date` and `end_date` explicitly.
- `start_date` (optional, range mode only): Start date in YYYY-MM-DD format (defaults to yesterday)
- `end_date` (optional): End date in YYYY-MM-DD format (defaults to today)
- `no_email` (optional): `1`, `true`, or `yes` to skip sending the email (report is still archived to project Files)

#### Send Weekly Report

Generates and emails the weekly report showing closed tickets. Defaults to the previous full week (Sunday–Sunday), filtered by ticket close date.

```bash
rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `start_date` (optional): Start of date range in YYYY-MM-DD format (defaults to previous Sunday)
- `end_date` (optional): End of date range in YYYY-MM-DD format (defaults to most recent Sunday)
- `no_email` (optional): `1`, `true`, or `yes` to skip sending the email (report is still archived to project Files)

#### Send Monthly Report

Generates and emails the monthly report showing account statuses for a target system.

```bash
rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="Oracle / SFMS" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `target_system` (required): Target system name (e.g., "Oracle / SFMS", "AIX", "SFS")
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `mode` (optional): "current" (live snapshot) or "monthly" (end-of-month snapshot, default: "monthly")
- `month` (optional): Month number 1-12 (for monthly mode, default: current month)
- `year` (optional): Year (for monthly mode, default: current year)
- `no_email` (optional): `1`, `true`, or `yes` to skip sending the email (report is still archived to project Files)

#### Audit Account Holder Info

Reconciles cached **Account Holder** custom field values on tickets
(Account Holder Name, Email, Phone, Status, UID, Office) against the
authoritative data source for each Account Holder:

- ESS API for Employees
- `tracked_users` table for Vendors and Volunteers

Only tickets whose tracker has both the Account Holder Type and ID custom
fields enabled are audited; tickets on other trackers are ignored.

For each distinct (Account Holder Type, Account Holder ID) appearing on
in-scope issues the task fetches the current authoritative record,
diffs it against the cached custom field values, and writes back any
drifted fields. Changes are recorded in the ticket's **History / Property
Changes** view (with watcher email notifications suppressed). Tickets that
can't be matched to an account holder are listed as **Unmatched** (and
flagged "review needed" in the summary), including any missing the Account
Holder Type and/or ID needed for the lookup.

Produces a single CSV which is:
1. Emailed to the configured recipients (see email behavior below).
2. Archived to the project's Files repository.

The email is only sent when the audit finds changes or unmatched tickets.
When a run turns up nothing actionable, no email is sent (the CSV is still
archived); pass `force_email=1` to send the email regardless. This applies
to dry runs too.

If email delivery fails the archive still runs and the operator is
warned, so the audit record is never lost.

```bash
# Apply mode (default): writes corrections to tickets
rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" RAILS_ENV=production

# Dry run: report drift without changing any tickets
rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" dry_run=1 RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `dry_run` (optional): `1`, `true`, or `yes` to skip writes and only report drift
- `force_email` (optional): `1`, `true`, or `yes` to always send the email even when there are no changes or unmatched tickets
- `no_email` (optional): `1`, `true`, or `yes` to never send the email (report is still archived to project Files); takes precedence over `force_email`

#### Send All-Systems Monthly Report

Generates and emails the monthly report for **all configured target systems** as a single ZIP attachment containing one CSV per system.

```bash
rake nysenate_audit_utils:send_all_systems_monthly_report project_id="bachelp-2" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated list of email addresses (uses configured default if not provided)
- `mode` (optional): "current" (live snapshot) or "monthly" (end-of-month snapshot, default: "monthly")
- `month` (optional): Month number 1-12 (for monthly mode, default: current month)
- `year` (optional): Year (for monthly mode, default: current year)
- `no_email` (optional): `1`, `true`, or `yes` to skip sending the email (report is still archived to project Files)

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
