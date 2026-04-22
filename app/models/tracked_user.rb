# frozen_string_literal: true

class TrackedUser < ActiveRecord::Base
  self.table_name = 'tracked_users'

  VALID_TYPES = %w[Vendor].freeze
  VALID_STATUSES = %w[Active Inactive].freeze

  # Validations
  validates :user_type, presence: true, inclusion: { in: VALID_TYPES }
  validates :user_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }

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
  def self.next_tracked_user_id
    offset = begin
      Setting.plugin_nysenate_audit_utils['tracked_user_id_offset'].to_i
    rescue StandardError
      500_000
    end
    offset = 500_000 if offset <= 0

    max_id = maximum(:user_id).to_i  # nil.to_i => 0

    [max_id, offset].max + 1
  end
end
