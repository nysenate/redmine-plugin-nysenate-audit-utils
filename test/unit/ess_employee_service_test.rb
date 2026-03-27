require File.expand_path('../../test_helper', __FILE__)

class EssEmployeeServiceTest < ActiveSupport::TestCase
  def setup
    @api_client_mock = mock('api_client')
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:api_client).returns(@api_client_mock)
  end

  def test_search_returns_employees_for_valid_response
    api_response = {
      'success' => true,
      'result' => [
        sample_employee_data(12345, 'jsmith', 'John', 'Smith'),
        sample_employee_data(12346, 'mjones', 'Mary', 'Jones')
      ]
    }

    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'smith',
      limit: 20,
      offset: 0
    }).returns(api_response)

    employees = NysenateAuditUtils::Ess::EssEmployeeService.search('smith')

    assert_equal 2, employees.length
    assert_equal 12345, employees.first.employee_id
    assert_equal 'jsmith', employees.first.uid
    assert_equal 'John', employees.first.first_name
  end

  def test_search_with_custom_limit_and_offset
    api_response = {
      'success' => true,
      'result' => [sample_employee_data(12345, 'jsmith', 'John', 'Smith')]
    }

    # Plugin uses 0-based offset=100, which translates to ESS 1-based offset=101
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 50,
      offset: 101
    }).returns(api_response)

    employees = NysenateAuditUtils::Ess::EssEmployeeService.search('test', limit: 50, offset: 100)

    assert_equal 1, employees.length
  end

  def test_search_validates_limit_bounds
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 20,
      offset: 0
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', limit: 0)

    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 1000,
      offset: 0
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', limit: 5000)
  end

  def test_search_validates_offset_bounds
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 20,
      offset: 0
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', offset: -10)
  end

  def test_search_omits_empty_term_param
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      limit: 20,
      offset: 0
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('')
  end

  def test_search_returns_empty_array_for_failed_response
    @api_client_mock.expects(:get).returns({'success' => false})

    employees = NysenateAuditUtils::Ess::EssEmployeeService.search('test')

    assert_equal [], employees
  end

  def test_search_returns_empty_array_for_nil_response
    @api_client_mock.expects(:get).returns(nil)

    employees = NysenateAuditUtils::Ess::EssEmployeeService.search('test')

    assert_equal [], employees
  end

  def test_find_by_id_returns_employee_for_valid_response
    api_response = {
      'success' => true,
      'employee' => sample_employee_data(12345, 'jsmith', 'John', 'Smith')
    }

    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/12345').returns(api_response)

    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(12345)

    assert_not_nil employee
    assert_equal 12345, employee.employee_id
    assert_equal 'jsmith', employee.uid
  end

  def test_find_by_id_returns_nil_for_failed_response
    @api_client_mock.expects(:get).returns({'success' => false})

    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(12345)

    assert_nil employee
  end

  def test_find_by_id_returns_nil_for_blank_id
    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id('')
    assert_nil employee

    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(nil)
    assert_nil employee
  end

  def test_find_by_id_returns_nil_for_nil_response
    @api_client_mock.expects(:get).returns(nil)

    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(12345)

    assert_nil employee
  end

  def test_find_by_id_returns_nil_for_missing_employee_data
    @api_client_mock.expects(:get).returns({'success' => true, 'employee' => nil})

    employee = NysenateAuditUtils::Ess::EssEmployeeService.find_by_id(12345)

    assert_nil employee
  end

  # Tests for 0-based to 1-based offset translation
  # Plugin uses standard 0-based indexing, ESS API uses 1-based indexing

  def test_offset_translation_zero_offset_stays_zero
    # Special case: offset=0 maps to ESS offset=0 (positions 1-20)
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 20,
      offset: 0
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', offset: 0)
  end

  def test_offset_translation_first_page_to_second_page
    # Plugin offset=20 (records 20-39) → ESS offset=21 (positions 21-40)
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 20,
      offset: 21
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', offset: 20)
  end

  def test_offset_translation_second_page_to_third_page
    # Plugin offset=40 (records 40-59) → ESS offset=41 (positions 41-60)
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'test',
      limit: 20,
      offset: 41
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('test', offset: 40)
  end

  def test_offset_translation_prevents_duplicate_at_page_boundary
    # This test verifies the fix for the pagination bug
    # Without translation: plugin offset=20 → ESS offset=20 → duplicate at position 20
    # With translation: plugin offset=20 → ESS offset=21 → no duplicate
    @api_client_mock.expects(:get).with('/api/v1/bachelp/employee/search', {
      term: 'richard',
      limit: 20,
      offset: 21
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssEmployeeService.search('richard', limit: 20, offset: 20)
  end

  private

  def sample_employee_data(id, uid, first_name, last_name)
    {
      'employeeId' => id,
      'uid' => uid,
      'firstName' => first_name,
      'lastName' => last_name,
      'fullName' => "#{first_name} A. #{last_name}",
      'email' => "#{uid}@nysenate.gov",
      'workPhone' => '(518) 555-0123',
      'active' => true
    }
  end
end