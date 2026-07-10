# NY Senate Audit Utils Plugin

A comprehensive Redmine plugin providing audit utilities, user data integration, and security workflow tools for the New York State Senate.

## Quick Start

### Installation

*Note: Prefix `rake` commands with `bundle exec` if using Bundler.*

1. Clone the plugin to the `plugins/nysenate_audit_utils` directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone git@github.com:nysenate/redmine-plugin-nysenate-audit-utils.git nysenate_audit_utils
   ```

1. Install dependencies with `bundle install` (or `gem install webmock` if not using Bundler).

1. Run plugin migrations from the Redmine root:
   ```bash
   cd /path/to/redmine
   rake redmine:plugins:migrate NAME=nysenate_audit_utils RAILS_ENV=production
   ```

1. Restart Redmine.

1. Configure the plugin at **Administration → Plugins → NY Senate Audit Utils → Configure**.

(Optional) Verify the install with `rake redmine:plugins:test NAME=nysenate_audit_utils`.

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

The plugin stores user and request data in custom fields. Ensure the following
fields exist and are enabled on the desired projects/trackers, then map them
under **Administration → Plugins → Configure**:

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
- `Requested By` - User (single) — auto-populated on removal tickets (see [Removal Ticket Defaults](#removal-ticket-defaults))
- `Authorizing Users` - User (multiple) — auto-populated on removal tickets (see [Removal Ticket Defaults](#removal-ticket-defaults))

**Reporting Fields:**
- `BAC #` - Text — legacy BAC ticket number shown on the Quarterly/Annual report. The value may be blank once the legacy system is retired, but the field mapping must still be configured.

Use **"Auto-Configure All Fields"** to detect fields by name; if auto-detection
fails, select field IDs manually. Status indicators (✓ / ✗) confirm which
required fields are mapped.

#### Removal Ticket Defaults

Select a single Redmine user to auto-populate as both the **Requested By** and
**Authorizing Users** fields whenever a removal ticket is created from the Daily
Report. Leave it unset to leave those fields blank. Requires the `Requested By`
and `Authorizing Users` fields to be mapped above.

### 3. Project Module

Enable the **Audit Utils** module per-project at **Projects → \*your project\*
→ Settings → Modules** to activate the reporting, autofill, packet creation, and
tracked-user features described below.

### 4. Permissions

Under **Administration → Roles and Permissions**, grant roles the desired
permissions in the **Audit Utils** group:

- **View audit reports** - Access to daily/weekly/monthly reports
- **Export audit reports** - Export reports to CSV
- **Use user autofill** - User search and autofill functionality
- **Create ticket packets** - Generate ticket packets (PDF + attachments)
- **Manage Vendors/Volunteers** - Create/edit/delete vendor, volunteer, and contractor records

Assign the role(s) to users under **Projects → \*your project\* → Settings → Members**.

### 5. Email Reporting Configuration (Optional)

Set **Default Report Recipients** (comma-separated email addresses) in the
**Email Reporting Configuration** section of the plugin settings. This is the
default recipient list for all report rake tasks; individual tasks can override
it with a `recipients` parameter. Schedule reports with cron jobs (see
[Rake Tasks](#rake-tasks)).

Redmine's email delivery must be configured in `config/configuration.yml`
before the email-sending rake tasks will work. Example SMTP configuration:

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

## Features

### Reporting

Access via the project menu: **Reports → Audit Utils**. Report types:

- **Daily Reports**: Employees with recent status changes, with inline actions
  to create pre-filled account-request and removal tickets. Two modes — *Last
  Business Day* (default, single date) and *Date Range* (explicit start/end).
- **Weekly Reports**: Tickets closed during the previous full week (Sunday–Sunday).
- **Quarterly / Annual Reports**: Closed tickets for a single target system,
  feeding the SFMS Quarterly Audit and the SFS Annual Audit, with CSV columns
  matching the legacy audit spreadsheet.
- **Monthly Reports**: Account status snapshot for a target system.
- **Account Holder Access Report**: One row per account (account holder ×
  system) showing derived active/inactive status, filterable by search, account
  holder type, target system, and status.

On-screen reports use Redmine's standard pagination (preserving sort and
filters); CSV exports always contain the full, unpaginated dataset.

Reports can also be generated and emailed on a schedule via the rake tasks
described in [Rake Tasks](#rake-tasks).

### Ticket Packet Creation

Generate audit-ready zip packages containing a ticket's PDF plus all its
attachments. Available as a **Create Packet** button on the issue detail page,
or in bulk from the issue-list context menu.

### Tracked User Management

Manage non-employee tracked users (vendors, volunteers, contractors) at
**Administration → Manage Vendors/Volunteers** (admin-only): create, edit, and
delete records with auto-generated IDs (V1, V2, …). Employee data is read-only
from the ESS API.

### User Autofill

Real-time user search on issue pages with type selection (Employee, Vendor,
Volunteer), automatically populating the configured custom fields. Employee data
comes from the ESS API; vendor and volunteer data is managed locally.

### Request Code Mapping

Automatic request-type classification based on Account Action and Target System
combinations.

### ESS Integration

Employee search, retrieval, and status-change tracking (appointments,
terminations, transfers) via the ESS REST API.

## Rake Tasks

The plugin provides rake tasks for generating and emailing audit reports; run
them on a cron schedule to automate delivery. **Run all tasks from the Redmine
root directory.**

Each successful run archives a copy of the generated CSV/ZIP to the project's
**Files** repository (timestamped) for the audit trail. If the Files module is
disabled, archiving is skipped with a warning and the email is still sent.

Every email-sending task accepts a `no_email` flag (`1`, `true`, or `yes`) that
suppresses the email; the report is still generated and archived, and
`recipients` are not required in that mode.

### Send Daily Report

Generates and emails the daily report of employees with status changes.

```bash
# Default: Last Business Day mode for today (covers yesterday → today; Mondays cover Fri → Mon)
rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" RAILS_ENV=production

# Explicit date range
rake nysenate_audit_utils:send_daily_report project_id="bachelp-2" mode="range" start_date="2026-05-15" end_date="2026-05-17" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated email addresses (defaults to configured recipients)
- `mode` (optional): `business_day` (default, uses `end_date` only) or `range` (uses `start_date` and `end_date`)
- `start_date` (optional, range mode): YYYY-MM-DD (defaults to yesterday)
- `end_date` (optional): YYYY-MM-DD (defaults to today)
- `no_email` (optional): skip sending the email (report is still archived)

### Send Weekly Report

Generates and emails the report of tickets closed in the previous full week (Sunday–Sunday, by close date).

```bash
rake nysenate_audit_utils:send_weekly_report project_id="bachelp-2" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated email addresses (defaults to configured recipients)
- `start_date` (optional): YYYY-MM-DD (defaults to previous Sunday)
- `end_date` (optional): YYYY-MM-DD (defaults to most recent Sunday)
- `no_email` (optional): skip sending the email (report is still archived)

### Send Monthly Report

Generates and emails the account-status snapshot for a target system.

```bash
rake nysenate_audit_utils:send_monthly_report project_id="bachelp-2" target_system="Oracle / SFMS" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `target_system` (required): Target system name (e.g. "Oracle / SFMS", "AIX", "SFS")
- `recipients` (optional): Comma-separated email addresses (defaults to configured recipients)
- `mode` (optional): `monthly` (end-of-month snapshot, default) or `current` (live snapshot)
- `month` (optional): 1–12, for monthly mode (defaults to current month)
- `year` (optional): for monthly mode (defaults to current year)
- `no_email` (optional): skip sending the email (report is still archived)

### Send All-Systems Monthly Report

Generates and emails a ZIP containing one monthly-snapshot CSV per configured target system.

```bash
rake nysenate_audit_utils:send_all_systems_monthly_report project_id="bachelp-2" RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated email addresses (defaults to configured recipients)
- `mode` (optional): `monthly` (default) or `current`
- `month` (optional): 1–12, for monthly mode (defaults to current month)
- `year` (optional): for monthly mode (defaults to current year)
- `no_email` (optional): skip sending the email (report is still archived)

### Audit Account Holder Info

Reconciles cached Account Holder custom field values on tickets against the
authoritative source (ESS for Employees, `tracked_users` for Vendors/Volunteers)
and writes back any drift, recording changes in each ticket's history. The email
is sent only when the run finds changes or unmatched tickets.

```bash
# Apply mode (default): writes corrections to tickets
rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" RAILS_ENV=production

# Dry run: report drift without changing any tickets
rake nysenate_audit_utils:audit_account_holder_info project_id="bachelp-2" dry_run=1 RAILS_ENV=production
```

**Options:**
- `project_id` (required): Project identifier or numeric ID
- `recipients` (optional): Comma-separated email addresses (defaults to configured recipients)
- `dry_run` (optional): skip writes and only report drift
- `force_email` (optional): always send the email, even with no changes or unmatched tickets
- `no_email` (optional): never send the email (report is still archived); takes precedence over `force_email`
