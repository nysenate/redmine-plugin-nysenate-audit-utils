# frozen_string_literal: true

class TrackedUser < ActiveRecord::Base
  self.table_name = 'tracked_users'

  VALID_TYPES = %w[Vendor].freeze
  VALID_STATUSES = %w[Active Inactive].freeze

  # Validations
  validates :user_type, presence: true, inclusion: { in: VALID_TYPES }
  validates :user_id, presence: true, uniqueness: { scope: :user_type }
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validate :user_id_format

  # Scopes
  scope :vendors, -> { where(user_type: 'Vendor') }
  scope :active, -> { where(status: 'Active') }
  scope :inactive, -> { where(status: 'Inactive') }

  # Instance methods
  def display_name
    "#{name} (#{user_id})"
  end

  def active?
    status == 'Active'
  end

  # Class methods
  def self.next_vendor_id
    last_vendor = where(user_type: 'Vendor')
                    .order(Arel.sql("CAST(SUBSTRING(user_id, 2) AS UNSIGNED) DESC"))
                    .first
    if last_vendor && last_vendor.user_id =~ /\AV(\d+)\z/
      next_num = ::Regexp.last_match(1).to_i + 1
    else
      next_num = 1
    end
    "V#{next_num}"
  end

  private

  def user_id_format
    case user_type
    when 'Vendor'
      unless user_id =~ /\AV\d+\z/
        errors.add(:user_id, "must start with 'V' followed by numbers (e.g., V1, V23)")
      end
    end
  end
end
