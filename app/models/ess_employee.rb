# frozen_string_literal: true

class EssEmployee
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :employee_id, :integer
  attribute :uid, :string
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :full_name, :string
  attribute :email, :string
  attribute :work_phone, :string
  attribute :active, :boolean
  attribute :location

  validates :employee_id, presence: true, numericality: { greater_than: 0 }
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :full_name, presence: true, length: { maximum: 200 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :work_phone, length: { maximum: 20 }, allow_blank: true
  validates :uid, length: { maximum: 50 }, allow_blank: true

  def initialize(attributes = {})
    if attributes.is_a?(Hash) && has_api_format?(attributes)
      mapped_attributes = map_api_attributes(attributes)
      super(mapped_attributes)
    else
      super
    end
  end

  def display_name
    full_name.presence || "#{first_name} #{last_name}"
  end

  def has_uid?
    uid.present?
  end

  def has_email?
    email.present?
  end

  def contact_info
    info = []
    info << email if email.present?
    info << work_phone if work_phone.present?
    info.join(', ')
  end

  def has_location?
    location.present?
  end

  def has_resp_center_head?
    location&.resp_center_head.present?
  end

  def resp_center_head
    location&.resp_center_head
  end

  def resp_center_display_name
    resp_center_head&.display_name
  end

  def resp_center_full_name
    resp_center_head&.full_display_name
  end

  def to_hash
    {
      employee_id: employee_id,
      uid: uid,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      email: email,
      work_phone: work_phone,
      active: active,
      location: location&.to_hash
    }
  end

  private

  def has_api_format?(attributes)
    attributes.key?('employeeId') || attributes.key?('firstName') || attributes.key?('lastName')
  end

  def map_api_attributes(api_response)
    mapped = {
      employee_id: api_response['employeeId'],
      uid: api_response['uid'],
      first_name: api_response['firstName'],
      last_name: api_response['lastName'],
      full_name: api_response['fullName'],
      email: api_response['email'],
      work_phone: api_response['workPhone'],
      active: api_response['active']
    }

    if api_response['location'].present?
      mapped[:location] = EssLocation.new(api_response['location'])
    end

    mapped
  end
end
