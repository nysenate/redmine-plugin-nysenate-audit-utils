# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class EssResponsibilityCenterHeadTest < ActiveSupport::TestCase
  def test_should_initialize_from_api_response
    api_data = {
      'active' => true,
      'code' => 'PARKER',
      'shortName' => 'SEN PARKER',
      'name' => 'Senator John A. Alpha',
      'affiliateCode' => 'MAJ'
    }

    resp_center = EssResponsibilityCenterHead.new(api_data)

    assert resp_center.active
    assert_equal 'PARKER', resp_center.code
    assert_equal 'SEN PARKER', resp_center.short_name
    assert_equal 'Senator John A. Alpha', resp_center.name
    assert_equal 'MAJ', resp_center.affiliate_code
  end

  def test_should_initialize_from_attributes_hash
    attrs = {
      active: false,
      code: 'PERSONNEL',
      short_name: 'PERSONNEL',
      name: 'Personnel Department',
      affiliate_code: 'ADM'
    }

    resp_center = EssResponsibilityCenterHead.new(attrs)

    refute resp_center.active
    assert_equal 'PERSONNEL', resp_center.code
    assert_equal 'PERSONNEL', resp_center.short_name
    assert_equal 'Personnel Department', resp_center.name
    assert_equal 'ADM', resp_center.affiliate_code
  end

  def test_should_validate_required_fields
    resp_center = EssResponsibilityCenterHead.new

    refute resp_center.valid?
    assert resp_center.errors[:code].present?
    assert resp_center.errors[:short_name].present?
    assert resp_center.errors[:name].present?
  end

  def test_should_allow_blank_affiliate_code
    resp_center = EssResponsibilityCenterHead.new(
      code: 'TEST',
      short_name: 'TEST',
      name: 'Test Department',
      affiliate_code: ''
    )

    assert resp_center.valid?
  end

  def test_should_validate_field_lengths
    resp_center = EssResponsibilityCenterHead.new(
      code: 'A' * 51,
      short_name: 'B' * 101,
      name: 'C' * 201,
      affiliate_code: 'D' * 11
    )

    refute resp_center.valid?
    assert resp_center.errors[:code].present?
    assert resp_center.errors[:short_name].present?
    assert resp_center.errors[:name].present?
    assert resp_center.errors[:affiliate_code].present?
  end

  def test_display_name_returns_short_name_when_present
    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator John A. Alpha'
    )

    assert_equal 'SEN PARKER', resp_center.display_name
  end

  def test_display_name_falls_back_to_name_then_code
    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: '',
      name: 'Senator John A. Alpha'
    )

    assert_equal 'Senator John A. Alpha', resp_center.display_name

    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: '',
      name: ''
    )

    assert_equal 'PARKER', resp_center.display_name
  end

  def test_full_display_name_returns_name_when_present
    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator John A. Alpha'
    )

    assert_equal 'Senator John A. Alpha', resp_center.full_display_name
  end

  def test_full_display_name_falls_back_to_short_name_then_code
    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: ''
    )

    assert_equal 'SEN PARKER', resp_center.full_display_name

    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: '',
      name: ''
    )

    assert_equal 'PARKER', resp_center.full_display_name
  end

  def test_active_returns_true_only_when_active_is_true
    resp_center = EssResponsibilityCenterHead.new(active: true)
    assert resp_center.active?

    resp_center = EssResponsibilityCenterHead.new(active: false)
    refute resp_center.active?

    resp_center = EssResponsibilityCenterHead.new(active: nil)
    refute resp_center.active?
  end

  def test_to_hash_returns_all_attributes
    resp_center = EssResponsibilityCenterHead.new(
      active: true,
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator John A. Alpha',
      affiliate_code: 'MAJ'
    )

    hash = resp_center.to_hash

    assert hash[:active]
    assert_equal 'PARKER', hash[:code]
    assert_equal 'SEN PARKER', hash[:short_name]
    assert_equal 'Senator John A. Alpha', hash[:name]
    assert_equal 'MAJ', hash[:affiliate_code]
  end
end