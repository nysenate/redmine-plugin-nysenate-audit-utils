# frozen_string_literal: true

class EssResponsibilityCenterHead
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :active, :boolean
  attribute :code, :string
  attribute :short_name, :string
  attribute :name, :string
  attribute :affiliate_code, :string

  validates :code, presence: true, length: { maximum: 50 }
  validates :short_name, presence: true, length: { maximum: 100 }
  validates :name, presence: true, length: { maximum: 200 }
  validates :affiliate_code, length: { maximum: 10 }, allow_blank: true

  def initialize(attributes = {})
    if attributes.is_a?(Hash) && has_api_format?(attributes)
      mapped_attributes = map_api_attributes(attributes)
      super(mapped_attributes)
    else
      super
    end
  end

  def display_name
    short_name.presence || name.presence || code
  end

  def full_display_name
    name.presence || short_name.presence || code
  end

  def active?
    active == true
  end

  def to_hash
    {
      active: active,
      code: code,
      short_name: short_name,
      name: name,
      affiliate_code: affiliate_code
    }
  end

  private

  def has_api_format?(attributes)
    attributes.key?('code') || attributes.key?('shortName') || attributes.key?('name')
  end

  def map_api_attributes(api_response)
    {
      active: api_response['active'],
      code: api_response['code'],
      short_name: api_response['shortName'],
      name: api_response['name'],
      affiliate_code: api_response['affiliateCode']
    }
  end
end
