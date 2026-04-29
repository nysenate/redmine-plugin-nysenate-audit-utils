require File.expand_path('../../test_helper', __FILE__)

class EmployeeDataSourceTest < ActiveSupport::TestCase
  def setup
    @data_source = NysenateAuditUtils::Users::EmployeeDataSource.new
  end

  # Test search

  def test_search_returns_normalized_employees
    ess_employee = EssEmployee.new(
      employee_id: 12345,
      uid: 'jdoe',
      first_name: 'John',
      last_name: 'Doe',
      full_name: 'John Doe',
      email: 'jdoe@nysenate.gov',
      work_phone: '518-555-0123',
      active: true
    )

    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:search).returns([ess_employee])

    results = @data_source.search('john')

    assert_equal 1, results.length

    result = results.first
    assert_equal 'Employee', result[:user_type]
    assert_equal '12345', result[:user_id]
    assert_equal 'John Doe', result[:name]
    assert_equal 'jdoe@nysenate.gov', result[:email]
    assert_equal '518-555-0123', result[:phone]
    assert_equal 'jdoe', result[:uid]
    assert_equal 'Active', result[:status]
  end

  def test_search_converts_inactive_status
    ess_employee = EssEmployee.new(
      employee_id: 12345,
      full_name: 'John Doe',
      active: false
    )

    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:search).returns([ess_employee])

    results = @data_source.search('john')

    assert_equal 'Inactive', results.first[:status]
  end

  def test_search_handles_location_office
    resp_center_head = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator Parker'
    )
    location = EssLocation.new(
      code: 'LOC123',
      location_description: 'Albany Office',
      resp_center_head: resp_center_head
    )

    ess_employee = EssEmployee.new(
      employee_id: 12345,
      full_name: 'John Doe',
      location: location,
      active: true
    )

    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:search).returns([ess_employee])

    results = @data_source.search('john')

    assert_equal 'PARKER', results.first[:location]
  end

  def test_search_passes_limit_and_offset
    NysenateAuditUtils::Ess::EssEmployeeService.expects(:search).with(
      'test',
      limit: 50,
      offset: 100
    ).returns([])

    @data_source.search('test', limit: 50, offset: 100)
  end

  # Test find_by_id

  def test_find_by_id_returns_normalized_employee
    ess_employee = EssEmployee.new(
      employee_id: 12345,
      full_name: 'John Doe',
      email: 'jdoe@nysenate.gov',
      active: true
    )

    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).with('12345').returns(ess_employee)

    result = @data_source.find_by_id('12345')

    assert_equal 'Employee', result[:user_type]
    assert_equal '12345', result[:user_id]
    assert_equal 'John Doe', result[:name]
  end

  def test_find_by_id_returns_nil_when_not_found
    NysenateAuditUtils::Ess::EssEmployeeService.stubs(:find_by_id).returns(nil)

    result = @data_source.find_by_id('99999')

    assert_nil result
  end

  # Test create raises error

  def test_create_raises_error
    error = assert_raises(RuntimeError) do
      @data_source.create(name: 'Test Employee')
    end
    assert_match(/cannot be created locally/, error.message)
  end

  # Test update raises error

  def test_update_raises_error
    error = assert_raises(RuntimeError) do
      @data_source.update('12345', {})
    end
    assert_match(/cannot be updated locally/, error.message)
  end

  # Test delete raises error

  def test_delete_raises_error
    error = assert_raises(RuntimeError) do
      @data_source.delete('12345')
    end
    assert_match(/cannot be deleted locally/, error.message)
  end
end
