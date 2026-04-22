# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class TrackedUserTest < ActiveSupport::TestCase
  def setup
    # Clean up any existing tracked users from previous tests
    TrackedUser.destroy_all

    @vendor = TrackedUser.new(
      user_type: 'Vendor',
      user_id: 500_999,
      name: 'Test Vendor',
      status: 'Active'
    )
  end

  def teardown
    # Clean up after each test
    TrackedUser.destroy_all
  end

  # Validation tests
  test 'should be valid with valid attributes' do
    assert @vendor.valid?
  end

  test 'should require user_type' do
    @vendor.user_type = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:user_type].present?
  end

  test 'should require user_id' do
    @vendor.user_id = nil
    assert_not @vendor.valid?
    assert @vendor.errors[:user_id].present?
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

  test 'should validate user_type inclusion' do
    @vendor.user_type = 'InvalidType'
    assert_not @vendor.valid?
    assert_includes @vendor.errors[:user_type], 'is not included in the list'
  end

  test 'should validate status inclusion' do
    @vendor.status = 'InvalidStatus'
    assert_not @vendor.valid?
    assert_includes @vendor.errors[:status], 'is not included in the list'
  end

  test 'should validate uniqueness of user_id' do
    @vendor.user_id = 500_001
    @vendor.save!

    duplicate = TrackedUser.new(
      user_type: 'Vendor',
      user_id: 500_001,
      name: 'Duplicate Vendor',
      status: 'Active'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], 'has already been taken'
  end

  # Scope tests
  test 'vendors scope should return only vendors' do
    vendor1 = TrackedUser.create!(user_type: 'Vendor', user_id: 500_100, name: 'Vendor 1', status: 'Active')
    vendor2 = TrackedUser.create!(user_type: 'Vendor', user_id: 500_101, name: 'Vendor 2', status: 'Inactive')

    vendors = TrackedUser.vendors
    assert_includes vendors, vendor1
    assert_includes vendors, vendor2
    assert_equal 'Vendor', vendors.first.user_type
  end

  test 'active scope should return only active tracked users' do
    active_vendor = TrackedUser.create!(user_type: 'Vendor', user_id: 500_200, name: 'Active Vendor', status: 'Active')
    inactive_vendor = TrackedUser.create!(user_type: 'Vendor', user_id: 500_201, name: 'Inactive Vendor', status: 'Inactive')

    active_tracked_users = TrackedUser.active
    assert_includes active_tracked_users, active_vendor
    assert_not_includes active_tracked_users, inactive_vendor
  end

  test 'inactive scope should return only inactive tracked users' do
    active_vendor = TrackedUser.create!(user_type: 'Vendor', user_id: 500_300, name: 'Active Vendor', status: 'Active')
    inactive_vendor = TrackedUser.create!(user_type: 'Vendor', user_id: 500_301, name: 'Inactive Vendor', status: 'Inactive')

    inactive_tracked_users = TrackedUser.inactive
    assert_includes inactive_tracked_users, inactive_vendor
    assert_not_includes inactive_tracked_users, active_vendor
  end

  # Instance method tests
  test 'display_name should return name with user_id' do
    @vendor.name = 'Test Company'
    @vendor.user_id = 500_042
    assert_equal 'Test Company (500042)', @vendor.display_name
  end

  test 'active? should return true for active tracked users' do
    @vendor.status = 'Active'
    assert @vendor.active?
  end

  test 'active? should return false for inactive tracked users' do
    @vendor.status = 'Inactive'
    assert_not @vendor.active?
  end

  # Class method tests
  test 'next_tracked_user_id should return offset+1 when no tracked users exist' do
    assert_equal 500_001, TrackedUser.next_tracked_user_id
  end

  test 'next_tracked_user_id should increment from highest existing ID' do
    TrackedUser.create!(user_type: 'Vendor', user_id: 500_005, name: 'Vendor 5', status: 'Active')
    assert_equal 500_006, TrackedUser.next_tracked_user_id
  end

  test 'next_tracked_user_id should handle non-sequential IDs' do
    TrackedUser.create!(user_type: 'Vendor', user_id: 500_001, name: 'Vendor 1', status: 'Active')
    TrackedUser.create!(user_type: 'Vendor', user_id: 500_010, name: 'Vendor 10', status: 'Active')
    TrackedUser.create!(user_type: 'Vendor', user_id: 500_003, name: 'Vendor 3', status: 'Active')
    assert_equal 500_011, TrackedUser.next_tracked_user_id
  end

  test 'next_tracked_user_id should work with large numbers' do
    TrackedUser.create!(user_type: 'Vendor', user_id: 509_999, name: 'Vendor 9999', status: 'Active')
    assert_equal 510_000, TrackedUser.next_tracked_user_id
  end

  test 'next_tracked_user_id should return offset+1 when all existing IDs are below offset' do
    TrackedUser.create!(user_type: 'Vendor', user_id: 42, name: 'Legacy Vendor', status: 'Active')
    assert_equal 500_001, TrackedUser.next_tracked_user_id
  end
end
