require File.expand_path('../../test_helper', __FILE__)

class EssStatusChangeTest < ActiveSupport::TestCase
  def test_should_initialize_from_api_response
    api_data = {
      'employeeId' => 12345,
      'uid' => 'jsmith',
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'email' => 'jsmith@nysenate.gov',
      'workPhone' => '(518) 555-0123',
      'active' => true,
      'transactionCode' => 'APP',
      'postDateTime' => '2023-08-15T10:30:00Z'
    }

    status_change = EssStatusChange.new(api_data)

    assert_equal 'APP', status_change.transaction_code
    assert_not_nil status_change.post_date_time
    assert_equal 12345, status_change.employee.employee_id
    assert_equal 'jsmith', status_change.employee.uid
  end

  def test_should_validate_transaction_code
    status_change = EssStatusChange.new(
      transaction_code: 'INVALID'
    )

    refute status_change.valid?
    assert status_change.errors[:transaction_code].present?

    EssStatusChange::TRANSACTION_CODES.keys.each do |code|
      status_change = EssStatusChange.new(
        transaction_code: code,
        employee_data: valid_employee_data
      )
      status_change.instance_variable_set(:@employee, EssEmployee.new(valid_employee_data))
      
      assert status_change.valid?, "#{code} should be valid"
    end
  end

  def test_should_validate_employee_presence
    status_change = EssStatusChange.new(
      transaction_code: 'APP'
    )

    refute status_change.valid?
    assert status_change.errors[:employee].present?
  end

  def test_transaction_description_returns_human_readable_text
    status_change = EssStatusChange.new(transaction_code: 'APP')
    assert_equal 'Employee appointment/hiring', status_change.transaction_description

    status_change = EssStatusChange.new(transaction_code: 'EMP')
    assert_equal 'Termination', status_change.transaction_description

    status_change = EssStatusChange.new(transaction_code: 'UNKNOWN')
    assert_equal 'UNKNOWN', status_change.transaction_description
  end

  def test_to_hash_includes_employee_and_transaction_data
    api_data = {
      'employeeId' => 12345,
      'uid' => 'jsmith',
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'email' => 'jsmith@nysenate.gov',
      'workPhone' => '(518) 555-0123',
      'active' => true,
      'transactionCode' => 'APP',
      'postDateTime' => '2023-08-15T10:30:00Z'
    }

    status_change = EssStatusChange.new(api_data)
    hash = status_change.to_hash

    assert_equal 12345, hash[:employee_id]
    assert_equal 'jsmith', hash[:uid]
    assert_equal 'APP', hash[:transaction_code]
    assert_equal 'Employee appointment/hiring', hash[:transaction_description]
    assert_not_nil hash[:post_date_time]
  end

  def test_should_parse_various_datetime_formats
    test_cases = [
      ['2023-08-15T10:30:00Z', DateTime.parse('2023-08-15T10:30:00Z')],
      ['2023-08-15 10:30:00', DateTime.parse('2023-08-15 10:30:00')],
      ['', nil],
      [nil, nil]
    ]

    test_cases.each do |input, expected|
      api_data = valid_api_data.merge('postDateTime' => input)
      status_change = EssStatusChange.new(api_data)
      
      if expected
        assert_equal expected.to_s, status_change.post_date_time.to_s
      else
        assert_nil status_change.post_date_time
      end
    end
  end

  def test_should_handle_invalid_datetime_gracefully
    api_data = valid_api_data.merge('postDateTime' => 'invalid-date')
    status_change = EssStatusChange.new(api_data)
    
    assert_nil status_change.post_date_time
  end

  private

  def valid_employee_data
    {
      'employeeId' => 12345,
      'uid' => 'jsmith',
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'email' => 'jsmith@nysenate.gov',
      'workPhone' => '(518) 555-0123',
      'active' => true
    }
  end

  def valid_api_data
    valid_employee_data.merge({
      'transactionCode' => 'APP',
      'postDateTime' => '2023-08-15T10:30:00Z'
    })
  end
end