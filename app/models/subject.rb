# frozen_string_literal: true

class Subject < ActiveRecord::Base
  VALID_TYPES = %w[Vendor].freeze
  VALID_STATUSES = %w[Active Inactive].freeze

  # Validations
  validates :subject_type, presence: true, inclusion: { in: VALID_TYPES }
  validates :subject_id, presence: true, uniqueness: { scope: :subject_type }
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validate :subject_id_format

  # Scopes
  scope :vendors, -> { where(subject_type: 'Vendor') }
  scope :active, -> { where(status: 'Active') }
  scope :inactive, -> { where(status: 'Inactive') }

  # Instance methods
  def display_name
    "#{name} (#{subject_id})"
  end

  def active?
    status == 'Active'
  end

  # Class methods
  def self.next_vendor_id
    last_vendor = where(subject_type: 'Vendor')
                    .order(Arel.sql("CAST(SUBSTRING(subject_id, 2) AS UNSIGNED) DESC"))
                    .first
    if last_vendor && last_vendor.subject_id =~ /\AV(\d+)\z/
      next_num = ::Regexp.last_match(1).to_i + 1
    else
      next_num = 1
    end
    "V#{next_num}"
  end

  private

  def subject_id_format
    case subject_type
    when 'Vendor'
      unless subject_id =~ /\AV\d+\z/
        errors.add(:subject_id, "must start with 'V' followed by numbers (e.g., V1, V23)")
      end
    end
  end
end
