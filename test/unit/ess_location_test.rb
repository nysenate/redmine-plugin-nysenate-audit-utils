# frozen_string_literal: true

require_relative '../test_helper'

class EssLocationTest < ActiveSupport::TestCase
  def test_should_initialize_with_basic_attributes
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      location_type: 'Work Location',
      location_type_code: 'W',
      location_description: '3021 TILDEN AVE',
      active: true
    )

    assert_equal 'D21001-W', location.loc_id
    assert_equal 'D21001', location.code
    assert_equal 'Work Location', location.location_type
    assert_equal 'W', location.location_type_code
    assert_equal '3021 TILDEN AVE', location.location_description
    assert location.active?
  end

  def test_should_initialize_from_api_response
    api_data = {
      'locId' => 'D21001-W',
      'code' => 'D21001',
      'locationType' => 'Work Location',
      'locationTypeCode' => 'W',
      'locationDescription' => '3021 TILDEN AVE',
      'active' => true,
      'address' => {
        'addr1' => '3021 Tilden Ave',
        'city' => 'Brooklyn',
        'state' => 'NY',
        'zip5' => '11226'
      },
      'respCenterHead' => {
        'active' => true,
        'code' => 'PARKER',
        'shortName' => 'SEN PARKER',
        'name' => 'Senator Kevin S. Parker',
        'affiliateCode' => 'MAJ'
      }
    }

    location = EssLocation.new(api_data)

    assert_equal 'D21001-W', location.loc_id
    assert_equal 'D21001', location.code
    assert location.has_address?
    assert_kind_of EssAddress, location.address
    assert location.has_resp_center_head?
    assert_kind_of EssResponsibilityCenterHead, location.resp_center_head
    assert_equal 'PARKER', location.resp_center_head.code
  end

  def test_should_handle_null_address
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      address: nil
    )

    refute location.has_address?
    assert_nil location.address
    assert_nil location.full_address
  end

  def test_should_handle_null_resp_center_head
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      resp_center_head: nil
    )

    refute location.has_resp_center_head?
    assert_nil location.resp_center_head
  end

  def test_display_name_should_prefer_description
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      location_description: '3021 TILDEN AVE'
    )

    assert_equal '3021 TILDEN AVE', location.display_name
  end

  def test_display_name_should_fallback_to_code
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001'
    )

    assert_equal 'D21001', location.display_name
  end

  def test_display_name_should_fallback_to_loc_id
    location = EssLocation.new(
      loc_id: 'D21001-W'
    )

    assert_equal 'D21001-W', location.display_name
  end

  def test_active_should_return_boolean
    active_location = EssLocation.new(active: true)
    inactive_location = EssLocation.new(active: false)
    nil_location = EssLocation.new(active: nil)

    assert active_location.active?
    refute inactive_location.active?
    refute nil_location.active?
  end

  def test_to_hash_should_include_all_fields
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      location_type: 'Work Location',
      location_type_code: 'W',
      location_description: '3021 TILDEN AVE',
      active: true
    )

    hash = location.to_hash

    assert_equal 'D21001-W', hash[:loc_id]
    assert_equal 'D21001', hash[:code]
    assert_equal 'Work Location', hash[:location_type]
    assert_equal 'W', hash[:location_type_code]
    assert_equal '3021 TILDEN AVE', hash[:location_description]
    assert_equal true, hash[:active]
    assert_nil hash[:address]
    assert_nil hash[:resp_center_head]
  end

  def test_to_hash_should_include_nested_objects
    api_data = {
      'locId' => 'D21001-W',
      'code' => 'D21001',
      'address' => {
        'addr1' => '3021 Tilden Ave',
        'city' => 'Brooklyn',
        'state' => 'NY'
      },
      'respCenterHead' => {
        'code' => 'PARKER',
        'shortName' => 'SEN PARKER',
        'name' => 'Senator Parker'
      }
    }

    location = EssLocation.new(api_data)
    hash = location.to_hash

    assert_kind_of Hash, hash[:address]
    assert_equal 'Brooklyn', hash[:address][:city]
    assert_kind_of Hash, hash[:resp_center_head]
    assert_equal 'PARKER', hash[:resp_center_head][:code]
  end

  def test_full_address_should_delegate_to_address
    api_data = {
      'locId' => 'D21001-W',
      'address' => {
        'addr1' => '3021 Tilden Ave',
        'city' => 'Brooklyn',
        'state' => 'NY',
        'zip5' => '11226'
      }
    }

    location = EssLocation.new(api_data)

    assert location.full_address.present?
    assert location.full_address.include?('Brooklyn')
  end

  def test_validates_length_constraints
    long_string = 'a' * 300

    location = EssLocation.new(
      loc_id: long_string,
      code: long_string,
      location_type: long_string,
      location_description: long_string
    )

    refute location.valid?
  end
end
