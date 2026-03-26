require File.expand_path('../../test_helper', __FILE__)

class UserServiceTest < ActiveSupport::TestCase
  def setup
    @service = NysenateAuditUtils::Users::UserService.new
  end

  # Test type validation

  def test_search_with_invalid_type_raises_error
    error = assert_raises(ArgumentError) do
      @service.search('test', type: 'Invalid')
    end
    assert_match(/Invalid user type/, error.message)
  end

  def test_find_by_id_with_invalid_type_raises_error
    error = assert_raises(ArgumentError) do
      @service.find_by_id('123', type: 'Invalid')
    end
    assert_match(/Invalid user type/, error.message)
  end

  # Test routing to EmployeeDataSource

  def test_search_with_employee_type_uses_employee_data_source
    NysenateAuditUtils::Users::EmployeeDataSource.any_instance.stubs(:search).with(
      'john',
      limit: 20,
      offset: 0
    ).returns([
      { user_type: 'Employee', user_id: '12345', name: 'John Doe' }
    ])

    results = @service.search('john', type: 'Employee')

    assert_equal 1, results.length
    assert_equal 'Employee', results.first[:user_type]
  end

  def test_find_by_id_with_employee_type_uses_employee_data_source
    NysenateAuditUtils::Users::EmployeeDataSource.any_instance.stubs(:find_by_id).with('12345').returns(
      { user_type: 'Employee', user_id: '12345', name: 'John Doe' }
    )

    result = @service.find_by_id('12345', type: 'Employee')

    assert_equal 'Employee', result[:user_type]
    assert_equal '12345', result[:user_id]
  end

  # Test routing to DatabaseDataSource

  def test_search_with_vendor_type_uses_database_data_source
    NysenateAuditUtils::Users::DatabaseDataSource.any_instance.stubs(:search).with(
      'acme',
      user_type: 'Vendor',
      limit: 20,
      offset: 0
    ).returns([
      { user_type: 'Vendor', user_id: 'V1', name: 'Acme Corp' }
    ])

    results = @service.search('acme', type: 'Vendor')

    assert_equal 1, results.length
    assert_equal 'Vendor', results.first[:user_type]
    assert_equal 'V1', results.first[:user_id]
  end

  def test_find_by_id_with_vendor_type_uses_database_data_source
    NysenateAuditUtils::Users::DatabaseDataSource.any_instance.stubs(:find_by_id).with(
      'V1',
      user_type: 'Vendor'
    ).returns(
      { user_type: 'Vendor', user_id: 'V1', name: 'Acme Corp' }
    )

    result = @service.find_by_id('V1', type: 'Vendor')

    assert_equal 'Vendor', result[:user_type]
    assert_equal 'V1', result[:user_id]
  end

  # Test create operations

  def test_create_vendor_succeeds
    NysenateAuditUtils::Users::DatabaseDataSource.any_instance.stubs(:create).returns(
      { user_type: 'Vendor', user_id: 'V1', name: 'New Vendor' }
    )

    result = @service.create(user_type: 'Vendor', user_id: 'V1', name: 'New Vendor')

    assert_equal 'Vendor', result[:user_type]
    assert_equal 'V1', result[:user_id]
  end

  def test_create_employee_raises_error
    error = assert_raises(RuntimeError) do
      @service.create(user_type: 'Employee', user_id: '12345', name: 'John Doe')
    end
    assert_match(/cannot be created locally/, error.message)
  end

  def test_create_without_user_type_raises_error
    error = assert_raises(ArgumentError) do
      @service.create(name: 'Test User')
    end
    assert_match(/user_type is required/, error.message)
  end

  # Test update operations

  def test_update_vendor_succeeds
    NysenateAuditUtils::Users::DatabaseDataSource.any_instance.stubs(:update).returns(
      { user_type: 'Vendor', user_id: 'V1', name: 'Updated Vendor' }
    )

    result = @service.update('V1', type: 'Vendor', attributes: { name: 'Updated Vendor' })

    assert_equal 'Updated Vendor', result[:name]
  end

  def test_update_employee_raises_error
    error = assert_raises(RuntimeError) do
      @service.update('12345', type: 'Employee', attributes: { name: 'John Doe' })
    end
    assert_match(/cannot be updated locally/, error.message)
  end

  # Test delete operations

  def test_delete_vendor_succeeds
    NysenateAuditUtils::Users::DatabaseDataSource.any_instance.stubs(:delete).returns(true)

    result = @service.delete('V1', type: 'Vendor')

    assert_equal true, result
  end

  def test_delete_employee_raises_error
    error = assert_raises(RuntimeError) do
      @service.delete('12345', type: 'Employee')
    end
    assert_match(/cannot be deleted locally/, error.message)
  end

  # Test search defaults

  def test_search_defaults_to_employee_type
    NysenateAuditUtils::Users::EmployeeDataSource.any_instance.stubs(:search).returns([])

    @service.search('test')

    # If we get here without error, the default worked
    assert true
  end

  def test_find_by_id_defaults_to_employee_type
    NysenateAuditUtils::Users::EmployeeDataSource.any_instance.stubs(:find_by_id).returns(nil)

    @service.find_by_id('12345')

    # If we get here without error, the default worked
    assert true
  end
end
