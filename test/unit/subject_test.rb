# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class SubjectTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing subjects from previous tests
    Subject.destroy_all

    @vendor = Subject.new(
      subject_type: 'Vendor',
      subject_id: 'V999',
      name: 'Test Vendor',
      status: 'Active'
    )
  end

  def teardown
    # Clean up after each test
    Subject.destroy_all
  end

  # Validation tests
  test 'should be valid with valid attributes' do
    assert @vendor.valid?
  end

  test 'should require subject_type' do
    @vendor.subject_type = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:subject_type].present?
  end

  test 'should require subject_id' do
    @vendor.subject_id = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:subject_id].present?
  end

  test 'should require name' do
    @vendor.name = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:name].present?
  end

  test 'should require status' do
    @vendor.status = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:status].present?
  end

  test 'should validate subject_type inclusion' do
    @vendor.subject_type = 'InvalidType'
    assert_not @vendor.valid?
    assert_includes @vendor.errors[:subject_type], 'is not included in the list'
  end

  test 'should validate status inclusion' do
    @vendor.status = 'InvalidStatus'
    assert_not @vendor.valid?
    assert_includes @vendor.errors[:status], 'is not included in the list'
  end

  test 'should validate uniqueness of subject_id scoped to subject_type' do
    @vendor.subject_id = 'V1'
    @vendor.save!

    duplicate = Subject.new(
      subject_type: 'Vendor',
      subject_id: 'V1',
      name: 'Duplicate Vendor',
      status: 'Active'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:subject_id], 'has already been taken'
  end

  # Prefix format validation tests
  test 'should accept valid vendor ID formats' do
    valid_ids = %w[V1 V23 V100 V9999]
    valid_ids.each do |id|
      @vendor.subject_id = id
      assert @vendor.valid?, "Expected #{id} to be valid, but got errors: #{@vendor.errors.full_messages}"
    end
  end

  test 'should reject invalid vendor ID formats' do
    invalid_ids = ['123', 'VendorA', 'V', 'VA1', 'v1', 'V-1', 'V 1', '']
    invalid_ids.each do |id|
      @vendor.subject_id = id
      assert_not @vendor.valid?, "Expected #{id.inspect} to be invalid"
      assert_includes @vendor.errors[:subject_id], "must start with 'V' followed by numbers (e.g., V1, V23)"
    end
  end

  # Scope tests
  test 'vendors scope should return only vendors' do
    vendor1 = Subject.create!(subject_type: 'Vendor', subject_id: 'V100', name: 'Vendor 1', status: 'Active')
    vendor2 = Subject.create!(subject_type: 'Vendor', subject_id: 'V101', name: 'Vendor 2', status: 'Inactive')

    vendors = Subject.vendors
    assert_includes vendors, vendor1
    assert_includes vendors, vendor2
    assert_equal 'Vendor', vendors.first.subject_type
  end

  test 'active scope should return only active subjects' do
    active_vendor = Subject.create!(subject_type: 'Vendor', subject_id: 'V200', name: 'Active Vendor', status: 'Active')
    inactive_vendor = Subject.create!(subject_type: 'Vendor', subject_id: 'V201', name: 'Inactive Vendor', status: 'Inactive')

    active_subjects = Subject.active
    assert_includes active_subjects, active_vendor
    assert_not_includes active_subjects, inactive_vendor
  end

  test 'inactive scope should return only inactive subjects' do
    active_vendor = Subject.create!(subject_type: 'Vendor', subject_id: 'V300', name: 'Active Vendor', status: 'Active')
    inactive_vendor = Subject.create!(subject_type: 'Vendor', subject_id: 'V301', name: 'Inactive Vendor', status: 'Inactive')

    inactive_subjects = Subject.inactive
    assert_includes inactive_subjects, inactive_vendor
    assert_not_includes inactive_subjects, active_vendor
  end

  # Instance method tests
  test 'display_name should return name with subject_id' do
    @vendor.name = 'Test Company'
    @vendor.subject_id = 'V42'
    assert_equal 'Test Company (V42)', @vendor.display_name
  end

  test 'active? should return true for active subjects' do
    @vendor.status = 'Active'
    assert @vendor.active?
  end

  test 'active? should return false for inactive subjects' do
    @vendor.status = 'Inactive'
    assert_not @vendor.active?
  end

  # Class method tests
  test 'next_vendor_id should return V1 when no vendors exist' do
    Subject.where(subject_type: 'Vendor').destroy_all
    assert_equal 'V1', Subject.next_vendor_id
  end

  test 'next_vendor_id should increment from last vendor ID' do
    Subject.where(subject_type: 'Vendor').destroy_all
    Subject.create!(subject_type: 'Vendor', subject_id: 'V5', name: 'Vendor 5', status: 'Active')
    assert_equal 'V6', Subject.next_vendor_id
  end

  test 'next_vendor_id should handle non-sequential IDs' do
    Subject.where(subject_type: 'Vendor').destroy_all
    Subject.create!(subject_type: 'Vendor', subject_id: 'V1', name: 'Vendor 1', status: 'Active')
    Subject.create!(subject_type: 'Vendor', subject_id: 'V10', name: 'Vendor 10', status: 'Active')
    Subject.create!(subject_type: 'Vendor', subject_id: 'V3', name: 'Vendor 3', status: 'Active')
    assert_equal 'V11', Subject.next_vendor_id
  end

  test 'next_vendor_id should work with large numbers' do
    Subject.where(subject_type: 'Vendor').destroy_all
    Subject.create!(subject_type: 'Vendor', subject_id: 'V9999', name: 'Vendor 9999', status: 'Active')
    assert_equal 'V10000', Subject.next_vendor_id
  end
end
