# Monthly Report Implementation Plan

## Overview

Create a monthly report showing the latest recorded account state for all employees with accounts on a selected target system. The report displays as a sortable table and offers CSV export functionality.

## Requirements

- Show latest account status for employees by target system
- One system displayed per report (user selects from dropdown)
- Table display with sorting capability
- CSV export for selected system
- Only include employees with closed tickets for the selected system

## Target Systems

- Oracle / SFMS
- SFS
- AIX
- NYSDS
- PayServ
- OGS Swiper Access

---

## Step 1: Add Efficient Bulk Query Method to AccountTrackingService ✅ COMPLETED

**Completed:** 2026-02-05

**Implementation Summary:**
- Added `get_account_statuses_by_system(target_system)` method to AccountTrackingService
- Implemented efficient bulk query strategy using joins/includes to avoid N+1 queries
- Added private helper methods: `find_closed_issues_by_target_system` and `build_account_statuses_by_employee`
- Created 8 comprehensive unit tests covering all scenarios
- All 30 tests pass (22 existing + 8 new)

### Files Modified
- `lib/nysenate_audit_utils/account_tracking/account_tracking_service.rb` (lines 78-337)
- `test/unit/account_tracking_service_test.rb` (lines 295-444)

### Implementation Details

Add `get_account_statuses_by_system(target_system)` method that:

1. **Single Bulk Query Strategy:**
   - Query all closed issues with the specified target_system value
   - Include employee_id, account_action, closed_on via custom field joins
   - Order by closed_on DESC to get most recent first
   - Use efficient ActiveRecord includes/joins to avoid N+1

2. **Data Processing:**
   - Group results by employee_id
   - For each employee, select the most recent (first) issue
   - Build account status hash with fields:
     - `employee_id`
     - `account_type` (target_system value)
     - `status` ("active" or "inactive" based on account_action)
     - `issue_id`
     - `closed_on`
     - `account_action`
     - `request_code` (from RequestCodeMapper)

3. **Return Value:**
   - Array of account status hashes
   - Sorted by employee_id for consistency
   - Empty array if no matches

### Method Signature
```ruby
def get_account_statuses_by_system(target_system)
  # Implementation
end
```

### Unit Tests

Create comprehensive tests in `test/unit/account_tracking_service_test.rb`:

1. **test_get_account_statuses_by_system_returns_correct_statuses**
   - Create closed issues for multiple employees on same system
   - Verify correct account statuses returned
   - Verify correct fields present in results

2. **test_get_account_statuses_by_system_returns_most_recent_only**
   - Create multiple closed issues for same employee and system
   - Verify only most recent issue is included
   - Verify older issues are excluded

3. **test_get_account_statuses_by_system_filters_by_system**
   - Create closed issues for multiple systems
   - Query for specific system
   - Verify only that system's issues are returned

4. **test_get_account_statuses_by_system_handles_empty_results**
   - Query for system with no closed issues
   - Verify returns empty array
   - Verify no errors raised

5. **test_get_account_statuses_by_system_excludes_open_issues**
   - Create both open and closed issues for same system
   - Verify only closed issues included

6. **test_get_account_statuses_by_system_determines_status_correctly**
   - Create issues with "Add" action (active)
   - Create issues with "Delete" action (inactive)
   - Verify status field is correct

7. **test_get_account_statuses_by_system_includes_request_code**
   - Create issues with various account_action/target_system combinations
   - Verify request_code is correctly mapped

8. **test_get_account_statuses_by_system_handles_blank_target_system**
   - Pass blank/nil target_system
   - Verify returns empty array or handles gracefully

---

## Step 2: Create MonthlyReportService ✅ COMPLETED

**Completed:** 2026-02-05

**Implementation Summary:**
- Created `MonthlyReportService` following pattern of DailyReportService and WeeklyReportService
- Implemented dynamic target system validation using custom field configuration
- Added employee name enrichment from custom field values
- Created 14 comprehensive unit tests covering all scenarios
- All 285 plugin tests pass (0 failures, 0 errors)
- Improved test helpers to support tracker association for custom fields

### Files Created
- `lib/nysenate_audit_utils/reporting/monthly_report_service.rb` (lines 1-105)
- `test/unit/monthly_report_service_test.rb` (lines 1-272)

### Files Modified
- `test/audit_test_helpers.rb` - Added tracker parameter to `create_or_find_field` and `setup_standard_bachelp_fields`
- `test/unit/account_tracking_service_test.rb` - Removed duplicate `create_or_find_field` method, now uses helper
- `test/unit/request_code_configuration_test.rb` - Fixed test isolation by clearing settings in setup

### Implementation Details

Create service class following pattern of DailyReportService and WeeklyReportService:

1. **Initialization:**
   ```ruby
   def initialize(target_system:)
     @target_system = target_system
     @errors = []
   end
   ```

2. **Main Entry Point:**
   ```ruby
   def generate
     validate_target_system
     fetch_account_statuses
     enrich_with_employee_names
     build_report_data
   rescue StandardError => e
     @errors << "Report generation failed: #{e.message}"
     Rails.logger.error("MonthlyReportService error: #{e.message}")
     nil
   end
   ```

3. **Data Fetching:**
   - Call `AccountTrackingService.get_account_statuses_by_system(@target_system)`
   - Get employee names from issue custom fields (Employee Name field)
   - Alternative: Optionally enrich from ESS API if needed

4. **Report Data Structure:**
   Each row contains:
   - `employee_id` - Employee ID
   - `employee_name` - Employee name from custom field or ESS
   - `account_type` - Target System value
   - `status` - "active" or "inactive"
   - `account_action` - Latest action (Add, Delete, Update, etc.)
   - `closed_on` - Date last issue was closed
   - `request_code` - Request code from mapper
   - `issue_id` - ID of most recent issue

5. **Success Tracking:**
   ```ruby
   def success?
     @errors.empty?
   end
   ```

### Unit Tests

Create tests in `test/unit/monthly_report_service_test.rb`:

1. **test_generate_returns_report_data_for_valid_system**
   - Set up test data with closed issues for target system
   - Call service.generate
   - Verify returns array of report data
   - Verify all expected fields present

2. **test_generate_returns_empty_array_for_system_with_no_data**
   - Call service with system that has no closed issues
   - Verify returns empty array
   - Verify success? returns true

3. **test_generate_includes_employee_names**
   - Create issues with Employee Name custom field populated
   - Verify employee_name included in report data

4. **test_generate_handles_missing_employee_name**
   - Create issues without Employee Name field
   - Verify report still generates
   - Verify employee_name is nil or empty string

5. **test_generate_sorts_by_employee_id**
   - Create multiple employees
   - Verify results sorted by employee_id

6. **test_generate_handles_errors_gracefully**
   - Mock AccountTrackingService to raise error
   - Verify errors array populated
   - Verify success? returns false
   - Verify generate returns nil

7. **test_generate_includes_all_required_fields**
   - Verify each row has: employee_id, employee_name, account_type, status, account_action, closed_on, request_code, issue_id

---

## Step 3: Add Controller Action for Monthly Report ✅ COMPLETED

**Completed:** 2026-02-05

**Implementation Summary:**
- Added `monthly` action to AuditReportsController following pattern of daily/weekly actions
- Implemented target system selection with default to 'Oracle / SFMS'
- Added sorting configuration for all monthly report columns (employee_id, employee_name, status, account_action, closed_on, request_code)
- Added CSV export with parameterized filename (includes system name and date)
- Created comprehensive view template with system dropdown, sortable table, and status badges
- Added 8 functional tests covering all scenarios
- All 293 plugin tests pass (0 failures, 0 errors)

### Files Modified
- `app/controllers/audit_reports_controller.rb` (lines 140-190, 336-364)
- `test/functional/audit_reports_controller_test.rb` (lines 160-324)

### Files Created
- `app/views/audit_reports/monthly.html.erb` (161 lines)

### Implementation Details

Add `monthly` action following pattern of `daily` and `weekly`:

1. **Action Implementation:**
   ```ruby
   def monthly
     # Parse target_system parameter
     target_system = params[:target_system].presence || 'Oracle / SFMS'

     # Generate report
     service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
       target_system: target_system
     )
     @report_data = service.generate
     @target_system = target_system

     # Handle errors
     unless service.success?
       @error_message = service.errors.join('; ')
       render :error
       return
     end

     # Set up sorting
     sort_init 'employee_id', 'asc'
     sort_update({
       'employee_id' => 'employee_id',
       'employee_name' => 'employee_name',
       'status' => 'status',
       'account_action' => 'account_action',
       'closed_on' => 'closed_on',
       'request_code' => 'request_code'
     })

     # Apply sorting
     if @report_data.present?
       @report_data = sort_report_data(@report_data)
     end

     # Respond to formats
     respond_to do |format|
       format.html
       format.csv do
         csv_data = generate_monthly_csv(@report_data)
         send_data csv_data,
                   filename: "monthly_report_#{target_system.parameterize}_#{Date.current.strftime('%Y%m%d')}.csv",
                   type: 'text/csv',
                   disposition: 'attachment'
       end
     end
   rescue => e
     Rails.logger.error "Monthly report generation failed: #{e.message}"
     @error_message = "Unable to generate report: #{e.message}"
     render :error
   end
   ```

2. **CSV Generation Method:**
   ```ruby
   def generate_monthly_csv(data)
     return '' unless data

     CSV.generate do |csv|
       # Header row
       csv << [
         'Employee ID',
         'Employee Name',
         'Status',
         'Account Action',
         'Last Updated',
         'Request Code',
         'Issue ID'
       ]

       # Data rows
       data.each do |row|
         csv << [
           row[:employee_id],
           row[:employee_name],
           row[:status],
           row[:account_action],
           row[:closed_on]&.strftime('%Y-%m-%d'),
           row[:request_code],
           row[:issue_id]
         ]
       end
     end
   end
   ```

### Functional Tests

Add tests to `test/functional/audit_reports_controller_test.rb`:

1. **test_monthly_report_success**
   - GET monthly_project_audit_reports_path
   - Assert response 200
   - Assert assigns @report_data
   - Assert assigns @target_system

2. **test_monthly_report_defaults_to_oracle_sfms**
   - GET without target_system param
   - Assert @target_system equals "Oracle / SFMS"

3. **test_monthly_report_respects_target_system_param**
   - GET with target_system: "AIX"
   - Assert @target_system equals "AIX"

4. **test_monthly_report_csv_export**
   - GET with format: :csv
   - Assert response content_type includes 'text/csv'
   - Assert filename includes target_system
   - Assert CSV content includes headers
   - Assert CSV includes data rows

5. **test_monthly_report_sorting**
   - GET with sort params for each column
   - Verify @report_data is sorted correctly

6. **test_monthly_report_handles_service_errors**
   - Mock service to return errors
   - Verify renders error template
   - Verify @error_message is set

7. **test_monthly_report_requires_authorization**
   - Test without proper permissions
   - Assert 403 or redirect

8. **test_monthly_report_csv_matches_html_data**
   - Generate report in HTML format
   - Generate report in CSV format
   - Verify data consistency

---

## Step 4: Create View Template

### Files to Create
- `app/views/audit_reports/monthly.html.erb`

### Implementation Details

Create view following pattern of daily.html.erb and weekly.html.erb:

1. **Header Section:**
   - Title: "Monthly Report"
   - Contextual links (CSV export, Back to Reports)
   - html_title helper

2. **System Selection Form:**
   ```erb
   <%= form_tag(monthly_project_audit_reports_path(@project), method: :get, id: "system-filter-form") do %>
     <fieldset class="box tabular">
       <legend>Target System</legend>
       <p>
         <%= label_tag :target_system, "Select System" %>
         <%= select_tag :target_system,
             options_for_select([
               'Oracle / SFMS',
               'SFS',
               'AIX',
               'NYSDS',
               'PayServ',
               'OGS Swiper Access'
             ], @target_system),
             class: "auto-submit" %>
       </p>
     </fieldset>
   <% end %>
   ```

3. **Report Info Section:**
   - Show selected system
   - Show employee count
   - Similar styling to daily/weekly reports

4. **Data Table:**
   - Sortable columns: Employee ID, Employee Name, Status, Account Action, Last Updated, Request Code, Issue
   - Status badges (green for active, red for inactive)
   - Issue ID as link to issue detail page
   - Request code display
   - Handle empty data with "No data" message

5. **JavaScript:**
   - Auto-submit form on system selection change

6. **CSS Styling:**
   - Consistent with daily/weekly reports
   - Status badges styling
   - Responsive table layout

### View Structure
```erb
<% html_title(l(:label_audit_monthly_report)) -%>

<div class="contextual">
  <%= link_to "Export CSV", monthly_project_audit_reports_path(@project, target_system: @target_system, format: :csv), class: "icon icon-download" %>
  <%= link_to "Back to Reports", project_audit_reports_path(@project), class: "icon icon-cancel" %>
</div>

<h2>Monthly Report</h2>

<!-- System selection form -->

<% if @report_data.nil? || @report_data.empty? %>
  <p class="nodata">No account data found for <%= @target_system %>.</p>
<% else %>
  <p class="report-info">
    Showing <%= pluralize(@report_data.size, 'employee') %> with accounts on <%= @target_system %>.
  </p>

  <table class="list issues <%= sort_css_classes %>">
    <thead>
      <tr>
        <%= sort_header_tag('employee_id', caption: 'Employee ID') %>
        <%= sort_header_tag('employee_name', caption: 'Employee Name') %>
        <%= sort_header_tag('status', caption: 'Status') %>
        <%= sort_header_tag('account_action', caption: 'Account Action') %>
        <%= sort_header_tag('closed_on', caption: 'Last Updated', default_order: 'desc') %>
        <%= sort_header_tag('request_code', caption: 'Request Code') %>
        <th>Issue</th>
      </tr>
    </thead>
    <tbody>
      <% @report_data.each do |row| %>
        <tr>
          <td><%= row[:employee_id] %></td>
          <td><%= row[:employee_name] || '—' %></td>
          <td>
            <span class="status-badge status-<%= row[:status] %>">
              <%= row[:status]&.titleize %>
            </span>
          </td>
          <td><%= row[:account_action] %></td>
          <td><%= row[:closed_on]&.strftime('%Y-%m-%d') || '—' %></td>
          <td><%= row[:request_code] || '—' %></td>
          <td>
            <%= link_to "##{row[:issue_id]}", issue_path(row[:issue_id]), target: '_blank' %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>

<!-- JavaScript and CSS -->
```

### Functional Test Coverage

Tests already covered in Step 3 functional tests will verify:
- View renders without errors
- Form elements present
- Table displays data correctly
- Links work correctly
- JavaScript auto-submit functions
- Empty state displays properly

---

## Step 5: Integration Testing and Refinement

### Files to Create (Optional)
- `test/integration/monthly_report_integration_test.rb`

### Integration Test Scenarios

1. **Complete User Workflow:**
   - Navigate to reports index
   - Click monthly report link
   - Verify default system loads
   - Change system selection
   - Verify report updates
   - Click CSV export
   - Verify CSV downloads

2. **Data Consistency Tests:**
   - Generate report in HTML
   - Generate same report in CSV
   - Verify data matches exactly
   - Verify sorting works the same

3. **Multiple Systems Test:**
   - Create data for all 6 systems
   - Visit each system report
   - Verify correct data shown for each
   - Verify no cross-contamination

4. **Edge Cases:**
   - System with no data
   - System with single employee
   - System with many employees (performance)
   - Employee with multiple account actions
   - Recent vs old closed tickets

5. **Performance Testing:**
   - Create realistic data volume (100+ employees)
   - Measure query time
   - Verify single query strategy used
   - Check for N+1 queries

### Manual Testing Checklist

- [ ] Monthly report accessible from reports index
- [ ] All 6 systems selectable from dropdown
- [ ] Default system displays on first load
- [ ] System selection auto-submits
- [ ] Table displays all expected columns
- [ ] Sorting works for each column
- [ ] Status badges show correct colors
- [ ] Issue links navigate to correct issue
- [ ] CSV export downloads correctly
- [ ] CSV filename includes system name and date
- [ ] CSV data matches HTML table
- [ ] Empty state displays when no data
- [ ] Back button returns to reports index
- [ ] Permissions enforced correctly

---

## Database Performance Considerations

### Query Optimization

The `get_account_statuses_by_system` method must be optimized to avoid N+1 queries:

**Bad Approach (N+1):**
```ruby
# DON'T DO THIS
employees.each do |employee_id|
  # Queries database for each employee
  get_account_statuses(employee_id).find { |s| s[:account_type] == target_system }
end
```

**Good Approach (Single Query):**
```ruby
# DO THIS
CustomValue
  .joins("INNER JOIN custom_values cv_action ON ...")
  .joins("INNER JOIN issues ON ...")
  .where(custom_field_id: target_system_field_id)
  .where(value: target_system)
  .where('issues.closed_on IS NOT NULL')
  .includes(:issue)
  .order('issues.closed_on DESC')
# Then group by employee_id in Ruby
```

### Expected Query Count

For a report with N employees:
- **Old approach:** 1 + N queries (fetch employees, then query each)
- **New approach:** 1-2 queries total (fetch all data, maybe one for field IDs)

---

## Localization

Add to `config/locales/en.yml`:
```yaml
en:
  label_audit_monthly_report: "Monthly Account Status Report"
```

---

## Route Configuration

Route already exists in `config/routes.rb`:
```ruby
get :monthly  # Line 8
```

---

## Summary of Files

### New Files (3)
1. `lib/nysenate_audit_utils/reporting/monthly_report_service.rb`
2. `test/unit/monthly_report_service_test.rb`
3. `app/views/audit_reports/monthly.html.erb`

### Modified Files (3)
1. `lib/nysenate_audit_utils/account_tracking/account_tracking_service.rb`
2. `test/unit/account_tracking_service_test.rb`
3. `app/controllers/audit_reports_controller.rb`
4. `test/functional/audit_reports_controller_test.rb`

### Total Test Coverage
- ~8 unit tests for AccountTrackingService
- ~7 unit tests for MonthlyReportService
- ~8 functional tests for controller
- Optional integration tests

**Estimated Total:** 23+ tests

---

## Enhancement: Point-in-Time Reporting ✅ COMPLETED

**Completed:** 2026-02-06

**Summary:** Added ability to view monthly reports as snapshots at specific points in time, with two modes: Monthly Snapshot (historical view) and Current State (latest data).

### Implementation Overview

This enhancement allows users to generate reports showing account statuses as they existed at a specific point in time, addressing the audit requirement to regenerate reports for past months.

### Changes Made

#### 1. AccountTrackingService Updates

**File:** `lib/nysenate_audit_utils/account_tracking/account_tracking_service.rb`

- Added `as_of_time` parameter to `get_account_statuses_by_system` method (default: `Time.current`)
- Added datetime filtering: `.where('issues.closed_on <= ?', as_of_time)`
- Updated `find_closed_issues_by_target_system` private method to accept and use `as_of_time`
- Only includes issues closed on or before the specified time

**Key Code:**
```ruby
def get_account_statuses_by_system(target_system, as_of_time: Time.current)
  # ... existing validation ...

  results = find_closed_issues_by_target_system(
    target_system,
    employee_id_field_id,
    account_action_field_id,
    target_system_field_id,
    as_of_time
  )
  # ...
end

def find_closed_issues_by_target_system(..., as_of_time)
  # ... existing queries ...

  closed_issues = Issue
    .where(id: issue_ids_with_target_system)
    .joins(:status)
    .where(issue_statuses: { is_closed: true })
    .where.not(closed_on: nil)
    .where('issues.closed_on <= ?', as_of_time)  # NEW
    .includes(:custom_values)
    .order(closed_on: :desc)
end
```

**Tests Added:** 5 new unit tests
- `test_get_account_statuses_by_system_filters_by_as_of_time`
- `test_get_account_statuses_by_system_includes_issue_closed_exactly_at_cutoff_time`
- `test_get_account_statuses_by_system_defaults_to_current_time_when_as_of_time_not_provided`
- `test_get_account_statuses_by_system_selects_most_recent_issue_before_cutoff`
- `test_get_account_statuses_by_system_returns_empty_when_all_issues_after_cutoff`

#### 2. MonthlyReportService Updates

**File:** `lib/nysenate_audit_utils/reporting/monthly_report_service.rb`

- Added `as_of_time` parameter to `initialize` (default: `Time.current`)
- Added `as_of_time` to `attr_reader`
- Passes `as_of_time` to `AccountTrackingService.get_account_statuses_by_system`

**Key Code:**
```ruby
def initialize(target_system:, as_of_time: Time.current)
  @target_system = target_system
  @as_of_time = as_of_time
  @errors = []
end

def fetch_account_statuses
  account_tracking_service = NysenateAuditUtils::AccountTracking::AccountTrackingService.new
  @account_statuses = account_tracking_service.get_account_statuses_by_system(
    @target_system,
    as_of_time: @as_of_time
  )
  # ...
end
```

**Tests Added:** 5 new unit tests
- `test_initializes_with_as_of_time_parameter`
- `test_defaults_as_of_time_to_current_time_when_not_provided`
- `test_generate_respects_as_of_time_parameter`
- `test_generate_includes_all_closed_issues_when_as_of_time_not_provided`
- `test_generate_selects_most_recent_issue_before_cutoff_time`

#### 3. Controller Updates

**File:** `app/controllers/audit_reports_controller.rb`

Added two-mode interface:
1. **Monthly Snapshot Mode** (default): View historical data as of a specific month
2. **Current State Mode**: View latest data for all accounts

**Key Code:**
```ruby
def monthly
  target_system = params[:target_system].presence || 'Oracle / SFMS'
  mode = params[:mode].presence || 'monthly'

  if mode == 'current'
    as_of_time = Time.current
    selected_month_num = nil
    selected_year = nil
  else
    # Monthly mode: snapshot at beginning of selected month
    selected_month_num = (params[:month].presence || Date.current.month).to_i
    selected_year = (params[:year].presence || Date.current.year).to_i
    as_of_time = Date.new(selected_year, selected_month_num, 1).beginning_of_month.in_time_zone
  end

  service = NysenateAuditUtils::Reporting::MonthlyReportService.new(
    target_system: target_system,
    as_of_time: as_of_time
  )
  # ...
end
```

**CSV Filename Updates:**
- Monthly mode: `monthly_report_oracle-sfms_202601.csv` (includes YYYYMM)
- Current mode: `monthly_report_oracle-sfms_current.csv`

**Tests Added:** 5 new functional tests
- `test_should_default_to_monthly_mode_with_current_month`
- `test_should_handle_monthly_mode_with_specific_month`
- `test_should_handle_current_mode_showing_latest_state`
- `test_should_include_month_in_CSV_filename_for_monthly_mode`
- `test_should_include_current_in_CSV_filename_for_current_mode`

#### 4. View Updates

**File:** `app/views/audit_reports/monthly.html.erb`

**Mode Selection Interface:**
```erb
<p>
  <%= label_tag :mode, "Report Mode" %><br/>
  <span class="radio-option" title="View account statuses as of the start of a specific month">
    <%= radio_button_tag :mode, 'monthly', @mode == 'monthly', onchange: "this.form.submit();" %>
    <%= label_tag :mode_monthly, "Monthly Snapshot", class: "inline" %>
  </span>
  <br/>
  <span class="radio-option" title="View latest status for all accounts (no time filtering)">
    <%= radio_button_tag :mode, 'current', @mode == 'current', onchange: "this.form.submit();" %>
    <%= label_tag :mode_current, "Current State", class: "inline" %>
  </span>
</p>
```

**Month/Year Selector (conditionally displayed):**
```erb
<% if @mode == 'monthly' %>
  <p id="month-selector">
    <%= label_tag :month, "Select Month/Year" %>
    <span class="month-year-selectors">
      <%= select_tag :month,
          options_for_select(
            Date::MONTHNAMES.compact.map.with_index(1) { |name, i| [name, i] },
            @selected_month_num || Date.current.month
          ),
          onchange: "this.form.submit();" %>
      <%= select_tag :year,
          options_for_select(
            (5.years.ago.year..Date.current.year).to_a.reverse,
            @selected_year || Date.current.year
          ),
          onchange: "this.form.submit();" %>
    </span>
  </p>
<% end %>
```

**Features:**
- Radio button mode selection with tooltips explaining each mode
- Month dropdown showing full month names (January, February, etc.)
- Year dropdown showing last 5 years in reverse chronological order
- All form controls auto-submit on change
- Report info displays appropriate message based on mode
- CSV export link includes mode and month/year parameters

**Styling:**
- Month dropdown: 130px wide
- Year dropdown: 85px wide
- Overrides `min-width: 200px` from general select styling
- Tooltips on radio buttons with `cursor: help`

### Design Decisions

1. **Default Behavior:** Monthly mode with current month selected
   - Rationale: Most common use case is viewing current month snapshot

2. **Time Precision:** Beginning of month (12:00 AM on 1st day)
   - Rationale: Aligns with monthly reporting cadence and audit requirements

3. **Custom Field Edits:** Included in report (not excluded)
   - Rationale: Post-close edits are typically corrections that should be reflected

4. **Implementation Approach:** Simple datetime filtering (Option 1)
   - Rationale: Custom field edits after close are rare and typically corrections
   - Alternative (journal-based reconstruction) available if needed in future

5. **UI Design:** Separate month/year dropdowns instead of HTML5 month picker
   - Rationale: Better browser compatibility and more familiar interface
   - Month names more readable than numeric values

### Test Coverage Summary

**Total:** 15 new tests added

- AccountTrackingService: 5 unit tests for time filtering
- MonthlyReportService: 5 unit tests for parameter passing
- AuditReportsController: 5 functional tests for mode handling

**All tests passing:** 308 runs, 958 assertions, 0 failures, 0 errors

### Future Enhancements

1. **Journal-Based Historical Reconstruction:** If custom field edits after close become common, implement journal-based reconstruction to track field value changes over time

2. **Date Range Reports:** Extend to support arbitrary date ranges instead of just beginning of month

3. **Comparison Reports:** Side-by-side comparison of two different time periods
