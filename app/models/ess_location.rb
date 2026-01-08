# frozen_string_literal: true

class EssLocation
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :loc_id, :string
  attribute :code, :string
  attribute :location_type, :string
  attribute :location_type_code, :string
  attribute :location_description, :string
  attribute :active, :boolean
  attribute :address
  attribute :resp_center_head

  validates :loc_id, length: { maximum: 50 }, allow_blank: true
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :location_type, length: { maximum: 100 }, allow_blank: true
  validates :location_description, length: { maximum: 200 }, allow_blank: true

  def initialize(attributes = {})
    if attributes.is_a?(Hash) && has_api_format?(attributes)
      mapped_attributes = map_api_attributes(attributes)
      super(mapped_attributes)
    else
      super
    end
  end

  def has_address?
    address.present?
  end

  def has_resp_center_head?
    resp_center_head.present?
  end

  def full_address
    address&.full_address
  end

  def display_name
    location_description.presence || code.presence || loc_id
  end

  def active?
    active == true
  end

  def to_hash
    {
      loc_id: loc_id,
      code: code,
      location_type: location_type,
      location_type_code: location_type_code,
      location_description: location_description,
      active: active,
      address: address&.to_hash,
      resp_center_head: resp_center_head&.to_hash
    }
  end

  private

  def has_api_format?(attributes)
    attributes.key?('locId') || attributes.key?('code') || attributes.key?('respCenterHead')
  end

  def map_api_attributes(api_response)
    mapped = {
      loc_id: api_response['locId'],
      code: api_response['code'],
      location_type: api_response['locationType'],
      location_type_code: api_response['locationTypeCode'],
      location_description: api_response['locationDescription'],
      active: api_response['active']
    }

    if api_response['address'].present?
      mapped[:address] = EssAddress.new(api_response['address'])
    end

    if api_response['respCenterHead'].present?
      mapped[:resp_center_head] = EssResponsibilityCenterHead.new(api_response['respCenterHead'])
    end

    mapped
  end
end
