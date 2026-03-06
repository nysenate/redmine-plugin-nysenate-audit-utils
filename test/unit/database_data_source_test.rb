require File.expand_path('../../test_helper', __FILE__)

class DatabaseDataSourceTest < ActiveSupport::TestCase
  def setup
    @data_source = NysenateAuditUtils::Subjects::DatabaseDataSource.new
  end

  # Test search

  def test_search_finds_vendors_by_name
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Acme Corp',
      email: 'contact@acme.com',
      status: 'Active'
    )

    results = @data_source.search('Acme', subject_type: 'Vendor')

    assert_equal 1, results.length
    assert_equal 'V1', results.first[:subject_id]
    assert_equal 'Acme Corp', results.first[:name]
  end

  def test_search_finds_vendors_by_id
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Acme Corp',
      status: 'Active'
    )

    results = @data_source.search('V1', subject_type: 'Vendor')

    assert_equal 1, results.length
    assert_equal 'V1', results.first[:subject_id]
  end

  def test_search_finds_vendors_by_email
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Acme Corp',
      email: 'contact@acme.com',
      status: 'Active'
    )

    results = @data_source.search('contact@acme', subject_type: 'Vendor')

    assert_equal 1, results.length
    assert_equal 'V1', results.first[:subject_id]
  end

  def test_search_returns_empty_array_when_no_matches
    results = @data_source.search('NonExistent', subject_type: 'Vendor')

    assert_equal 0, results.length
  end

  def test_search_respects_limit
    3.times do |i|
      Subject.create!(
        subject_type: 'Vendor',
        subject_id: "V#{i + 1}",
        name: "Test Vendor #{i + 1}",
        status: 'Active'
      )
    end

    results = @data_source.search('Test', subject_type: 'Vendor', limit: 2)

    assert_equal 2, results.length
  end

  def test_search_respects_offset
    3.times do |i|
      Subject.create!(
        subject_type: 'Vendor',
        subject_id: "V#{i + 1}",
        name: "Test Vendor #{i + 1}",
        status: 'Active'
      )
    end

    results = @data_source.search('Test', subject_type: 'Vendor', offset: 2)

    assert_equal 1, results.length
    assert_equal 'Test Vendor 3', results.first[:name]
  end

  def test_search_orders_by_name
    Subject.create!(subject_type: 'Vendor', subject_id: 'V1', name: 'Zebra Corp', status: 'Active')
    Subject.create!(subject_type: 'Vendor', subject_id: 'V2', name: 'Acme Corp', status: 'Active')

    results = @data_source.search('Corp', subject_type: 'Vendor')

    assert_equal 'Acme Corp', results.first[:name]
    assert_equal 'Zebra Corp', results.last[:name]
  end

  # Test find_by_id

  def test_find_by_id_returns_normalized_vendor
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Acme Corp',
      email: 'contact@acme.com',
      phone: '518-555-0100',
      uid: 'acme-user',
      location: 'Main Office',
      status: 'Active'
    )

    result = @data_source.find_by_id('V1', subject_type: 'Vendor')

    assert_equal 'Vendor', result[:subject_type]
    assert_equal 'V1', result[:subject_id]
    assert_equal 'Acme Corp', result[:name]
    assert_equal 'contact@acme.com', result[:email]
    assert_equal '518-555-0100', result[:phone]
    assert_equal 'acme-user', result[:uid]
    assert_equal 'Main Office', result[:location]
    assert_equal 'Active', result[:status]
  end

  def test_find_by_id_returns_nil_when_not_found
    result = @data_source.find_by_id('V99', subject_type: 'Vendor')

    assert_nil result
  end

  # Test create

  def test_create_creates_new_vendor
    result = @data_source.create(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'New Vendor',
      email: 'new@vendor.com',
      status: 'Active'
    )

    assert_equal 'Vendor', result[:subject_type]
    assert_equal 'V1', result[:subject_id]
    assert_equal 'New Vendor', result[:name]

    # Verify it was saved to database
    vendor = Subject.find_by(subject_id: 'V1')
    assert_not_nil vendor
    assert_equal 'New Vendor', vendor.name
  end

  def test_create_raises_error_on_invalid_data
    assert_raises(ActiveRecord::RecordInvalid) do
      @data_source.create(
        subject_type: 'Vendor',
        subject_id: 'invalid-id',  # Should fail validation (must be V + digits)
        name: 'Test Vendor'
      )
    end
  end

  # Test update

  def test_update_updates_existing_vendor
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Old Name',
      status: 'Active'
    )

    result = @data_source.update('V1', subject_type: 'Vendor', attributes: { name: 'New Name' })

    assert_equal 'New Name', result[:name]

    # Verify it was updated in database
    vendor.reload
    assert_equal 'New Name', vendor.name
  end

  def test_update_raises_error_when_not_found
    assert_raises(ActiveRecord::RecordNotFound) do
      @data_source.update('V99', subject_type: 'Vendor', attributes: { name: 'Test' })
    end
  end

  def test_update_raises_error_on_invalid_data
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Test Vendor',
      status: 'Active'
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      @data_source.update('V1', subject_type: 'Vendor', attributes: { name: '' })
    end
  end

  # Test delete

  def test_delete_removes_vendor
    vendor = Subject.create!(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Test Vendor',
      status: 'Active'
    )

    result = @data_source.delete('V1', subject_type: 'Vendor')

    assert_equal true, result

    # Verify it was deleted from database
    assert_nil Subject.find_by(subject_id: 'V1')
  end

  def test_delete_raises_error_when_not_found
    assert_raises(ActiveRecord::RecordNotFound) do
      @data_source.delete('V99', subject_type: 'Vendor')
    end
  end
end
