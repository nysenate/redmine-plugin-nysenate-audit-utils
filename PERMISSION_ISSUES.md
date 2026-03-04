# Employee Autofill Permission Issues - Investigation Findings

## Date
2026-02-12

## Issues Identified

### 1. Controller Permission Checks
**Problem**: `EmployeeSearchController` was checking **global** permissions instead of **project-level** permissions.

**Original Code** (`employee_search_controller.rb:62-65`):
```ruby
def check_permission
  unless User.current.allowed_to?(:use_employee_autofill, nil, global: true)
    render json: { error: "Access denied" }, status: :forbidden
  end
end
```

**Issue**: This checked if user has the permission globally across all projects, not for the specific project context.

**Fix Applied**: Changed to check project-level permission and module enablement:
```ruby
def check_permission
  project = find_project

  # Check if project exists and module is enabled
  unless project && project.module_enabled?(:audit_utils_employee_autofill)
    render json: { error: "Access denied" }, status: :forbidden
    return
  end

  # Check if user has permission for this project
  unless User.current.allowed_to?(:use_employee_autofill, project)
    render json: { error: "Access denied" }, status: :forbidden
  end
end
```

### 2. Hook Does Not Check Module Enablement
**Problem**: `NysenateAuditUtils::Autofill::Hooks#view_issues_form_details_bottom` was displaying the employee search widget even when:
- The Employee Autofill module was disabled for the project
- The user lacked the `use_employee_autofill` permission

**Original Code** (`lib/nysenate_audit_utils/autofill/hooks.rb:7-30`):
Only checked if tracker had employee fields, did not check module or permission.

**Fix Applied**: Added checks for module enablement and user permission:
```ruby
# Check if module is enabled for this project
unless issue.project.module_enabled?(:audit_utils_employee_autofill)
  return ''
end

# Check if user has permission for this project
unless User.current.allowed_to?(:use_employee_autofill, issue.project)
  return ''
end
```

## Tests Created

### Unit Tests (`test/unit/autofill_hooks_test.rb`)
Created 8 tests to verify hook behavior:
- Widget not shown when module disabled
- Widget not shown when user lacks permission
- Widget shown when module enabled AND user has permission
- Edge cases (no tracker, no fields, etc.)

### Functional Tests (`test/functional/employee_search_controller_test.rb`)
Added 8 new tests for project-level permission checking:
- Denies access when user lacks project permission
- Denies access when module not enabled
- Allows access when both conditions met
- Requires `project_id` parameter

## Test Failures Encountered

### Hook Tests
**Status**: 3/8 tests failing

**Failing Tests**:
1. `test_widget_shown_when_autofill_module_enabled`
2. `test_widget_only_shown_when_all_conditions_met`
3. `test_widget_shown_when_user_has_permission`

**Root Cause**: Permission system returns `false` even for admin users in test environment.

**Debug Output**:
```
Module enabled: true
User is admin: true
User has permission: false  <-- PROBLEM
```

**Analysis**:
- The `:use_employee_autofill` permission is defined under a `project_module` in `init.rb`
- Even admin users may need this permission explicitly granted to their role for project modules
- Test fixtures likely don't have roles with this permission set up
- Redmine's permission system for project modules may not automatically grant to admins

### Controller Tests
**Status**: All old tests updated successfully, new tests passing

## Outstanding Issues

### Permission Setup in Tests
**Problem**: Test environment doesn't properly configure the `:use_employee_autofill` permission for users.

**Options Considered**:
1. ~~Stub permission checks~~ - Doesn't actually test permission system (rejected)
2. ~~Manipulate roles per test~~ - Too complex and brittle (rejected)
3. **Fix test fixtures/setup** - Need to ensure roles in test fixtures include the permission
4. **Check admin bypass** - Verify if admins should automatically bypass project module permissions

**Recommendation**: Need to investigate:
- How Redmine handles admin permissions for project modules
- Whether test fixtures need to be updated with proper role permissions
- If there's a standard pattern in Redmine core tests for this scenario

## Files Modified

1. `app/controllers/employee_search_controller.rb` - Fixed permission checks ✅
2. `lib/nysenate_audit_utils/autofill/hooks.rb` - Added module/permission checks ✅
3. `test/unit/autofill_hooks_test.rb` - Created new unit tests ⚠️ (3 failing)
4. `test/functional/employee_search_controller_test.rb` - Updated and added tests ✅

## Next Steps

1. Determine correct approach for permission setup in unit tests
2. Fix the 3 failing hook unit tests
3. Test manually on dev server with both projects (with/without module enabled)
4. Verify admin and non-admin users behave correctly
