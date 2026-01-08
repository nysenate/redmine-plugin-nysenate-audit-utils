class EssStatusChange
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :transaction_code, :string
  attribute :post_date_time, :datetime
  
  attr_reader :employee

  TRANSACTION_CODES = {
    'APP' => 'Employee appointment/hiring',
    'LOC' => 'Location change',
    'NAM' => 'Name change',
    'PHO' => 'Phone number change',
    'RTP' => 'Re-appointment',
    'LIN' => 'Line number',
    'EMP' => 'Termination'
  }.freeze

  validates :transaction_code, presence: true, inclusion: { in: TRANSACTION_CODES.keys }
  validates :employee, presence: true

  def initialize(attributes = {})
    if attributes.is_a?(Hash) && has_api_format?(attributes)
      mapped_attributes = map_api_attributes(attributes)
      @employee = EssEmployee.new(mapped_attributes[:employee_data])
      super(mapped_attributes.except(:employee_data))
    elsif attributes.is_a?(Hash) && attributes[:employee_data]
      @employee = EssEmployee.new(attributes[:employee_data])
      super(attributes.except(:employee_data))
    else
      super(attributes)
      @employee = nil unless @employee
    end
  end

  def transaction_description
    TRANSACTION_CODES[transaction_code] || transaction_code
  end

  def to_hash
    employee.to_hash.merge({
      transaction_code: transaction_code,
      transaction_description: transaction_description,
      post_date_time: post_date_time
    })
  end

  private

  def has_api_format?(attributes)
    attributes.key?('transactionCode') && (attributes.key?('employeeId') || attributes.key?('firstName'))
  end

  def map_api_attributes(api_response)
    {
      transaction_code: api_response['transactionCode'],
      post_date_time: parse_datetime(api_response['postDateTime']),
      employee_data: api_response
    }
  end

  def parse_datetime(datetime_string)
    return nil if datetime_string.blank?
    
    begin
      DateTime.parse(datetime_string)
    rescue ArgumentError
      nil
    end
  end
end