# frozen_string_literal: true

class EssAddress
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :addr1, :string
  attribute :addr2, :string
  attribute :city, :string
  attribute :county, :string
  attribute :country, :string
  attribute :state, :string
  attribute :zip5, :string
  attribute :zip4, :string
  attribute :formatted_address_with_county, :string

  validates :city, length: { maximum: 100 }, allow_blank: true
  validates :county, length: { maximum: 100 }, allow_blank: true
  validates :state, length: { maximum: 50 }, allow_blank: true
  validates :zip5, length: { maximum: 10 }, allow_blank: true

  def initialize(attributes = {})
    if attributes.is_a?(Hash) && has_api_format?(attributes)
      mapped_attributes = map_api_attributes(attributes)
      super(mapped_attributes)
    else
      super
    end
  end

  def full_address
    formatted_address_with_county.presence || build_address
  end

  def street_address
    [addr1, addr2].reject(&:blank?).join(', ')
  end

  def city_state_zip
    parts = []
    parts << city if city.present?
    parts << state if state.present?
    parts << full_zip if full_zip.present?
    parts.join(', ')
  end

  def full_zip
    return nil if zip5.blank?
    zip4.present? ? "#{zip5}-#{zip4}" : zip5
  end

  def to_hash
    {
      addr1: addr1,
      addr2: addr2,
      city: city,
      county: county,
      country: country,
      state: state,
      zip5: zip5,
      zip4: zip4,
      formatted_address_with_county: formatted_address_with_county
    }
  end

  private

  def has_api_format?(attributes)
    attributes.key?('addr1') || attributes.key?('city') || attributes.key?('formattedAddressWithCounty')
  end

  def map_api_attributes(api_response)
    {
      addr1: api_response['addr1'],
      addr2: api_response['addr2'],
      city: api_response['city'],
      county: api_response['county'],
      country: api_response['country'],
      state: api_response['state'],
      zip5: api_response['zip5'],
      zip4: api_response['zip4'],
      formatted_address_with_county: api_response['formattedAddressWithCounty']
    }
  end

  def build_address
    parts = []
    parts << street_address if street_address.present?
    parts << city_state_zip if city_state_zip.present?
    parts.reject(&:blank?).join(', ')
  end
end
