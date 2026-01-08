require File.expand_path('../../test_helper', __FILE__)

class EssEmployeeTest < ActiveSupport::TestCase
  def test_should_initialize_from_api_response
    api_data = {
      'employeeId' => 12345,
      'uid' => 'jsmith',
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'email' => 'jsmith@nysenate.gov',
      'workPhone' => '(518) 555-0123',
      'active' => true
    }

    employee = EssEmployee.new(api_data)

    assert_equal 12345, employee.employee_id
    assert_equal 'jsmith', employee.uid
    assert_equal 'John', employee.first_name
    assert_equal 'Smith', employee.last_name
    assert_equal 'John A. Smith', employee.full_name
    assert_equal 'jsmith@nysenate.gov', employee.email
    assert_equal '(518) 555-0123', employee.work_phone
    assert employee.active
    assert_nil employee.resp_center_head
  end

  def test_should_initialize_from_attributes_hash
    attrs = {
      employee_id: 12345,
      uid: 'jsmith',
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John A. Smith',
      email: 'jsmith@nysenate.gov',
      work_phone: '(518) 555-0123',
      active: true
    }

    employee = EssEmployee.new(attrs)

    assert_equal 12345, employee.employee_id
    assert_equal 'jsmith', employee.uid
    assert_equal 'John', employee.first_name
  end

  def test_should_validate_required_fields
    employee = EssEmployee.new

    refute employee.valid?
    assert employee.errors[:employee_id].present?
    assert employee.errors[:first_name].present?
    assert employee.errors[:last_name].present?
    assert employee.errors[:full_name].present?
  end

  def test_should_validate_employee_id_is_positive
    employee = EssEmployee.new(employee_id: -1, first_name: 'John', last_name: 'Smith', full_name: 'John Smith')

    refute employee.valid?
    assert employee.errors[:employee_id].present?
  end

  def test_should_validate_email_format
    employee = EssEmployee.new(
      employee_id: 1,
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John Smith',
      email: 'invalid-email'
    )

    refute employee.valid?
    assert employee.errors[:email].present?
  end

  def test_should_allow_blank_email
    employee = EssEmployee.new(
      employee_id: 1,
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John Smith',
      email: ''
    )

    assert employee.valid?
  end

  def test_display_name_returns_full_name_when_present
    employee = EssEmployee.new(
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John A. Smith'
    )

    assert_equal 'John A. Smith', employee.display_name
  end

  def test_display_name_falls_back_to_first_last_name
    employee = EssEmployee.new(
      first_name: 'John',
      last_name: 'Smith',
      full_name: ''
    )

    assert_equal 'John Smith', employee.display_name
  end

  def test_has_uid_returns_true_when_uid_present
    employee = EssEmployee.new(uid: 'jsmith')
    assert employee.has_uid?

    employee = EssEmployee.new(uid: '')
    refute employee.has_uid?

    employee = EssEmployee.new(uid: nil)
    refute employee.has_uid?
  end

  def test_has_email_returns_true_when_email_present
    employee = EssEmployee.new(email: 'test@example.com')
    assert employee.has_email?

    employee = EssEmployee.new(email: '')
    refute employee.has_email?

    employee = EssEmployee.new(email: nil)
    refute employee.has_email?
  end

  def test_contact_info_combines_email_and_phone
    employee = EssEmployee.new(
      email: 'test@example.com',
      work_phone: '555-1234'
    )

    assert_equal 'test@example.com, 555-1234', employee.contact_info

    employee = EssEmployee.new(email: 'test@example.com')
    assert_equal 'test@example.com', employee.contact_info

    employee = EssEmployee.new(work_phone: '555-1234')
    assert_equal '555-1234', employee.contact_info
  end

  def test_to_hash_returns_all_attributes
    employee = EssEmployee.new(
      employee_id: 12345,
      uid: 'jsmith',
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John A. Smith',
      email: 'jsmith@nysenate.gov',
      work_phone: '(518) 555-0123',
      active: true
    )

    hash = employee.to_hash

    assert_equal 12345, hash[:employee_id]
    assert_equal 'jsmith', hash[:uid]
    assert_equal 'John', hash[:first_name]
    assert_equal 'Smith', hash[:last_name]
    assert_equal 'John A. Smith', hash[:full_name]
    assert_equal 'jsmith@nysenate.gov', hash[:email]
    assert_equal '(518) 555-0123', hash[:work_phone]
    assert hash[:active]
    assert_nil hash[:resp_center_head]
  end

  def test_should_initialize_from_api_response_with_resp_center_head
    api_data = {
      'employeeId' => 12345,
      'uid' => 'jsmith',
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'email' => 'jsmith@nysenate.gov',
      'workPhone' => '(518) 555-0123',
      'active' => true,
      'location' => {
        'locId' => 'D21001-W',
        'code' => 'D21001',
        'locationType' => 'Work Location',
        'locationTypeCode' => 'W',
        'locationDescription' => '3021 TILDEN AVE',
        'active' => true,
        'address' => {
          'addr1' => '3021 Tilden Ave',
          'city' => 'Brooklyn',
          'state' => 'NY',
          'zip5' => '11226'
        },
        'respCenterHead' => {
          'active' => true,
          'code' => 'PARKER',
          'shortName' => 'SEN PARKER',
          'name' => 'Senator John A. Alpha',
          'affiliateCode' => 'MAJ'
        }
      }
    }

    employee = EssEmployee.new(api_data)

    assert_equal 12345, employee.employee_id
    assert employee.has_location?
    assert_kind_of EssLocation, employee.location
    assert employee.has_resp_center_head?
    assert_kind_of EssResponsibilityCenterHead, employee.resp_center_head
    assert_equal 'PARKER', employee.resp_center_head.code
    assert_equal 'SEN PARKER', employee.resp_center_display_name
    assert_equal 'Senator John A. Alpha', employee.resp_center_full_name
  end

  def test_should_handle_null_resp_center_head
    api_data = {
      'employeeId' => 12345,
      'firstName' => 'John',
      'lastName' => 'Smith',
      'fullName' => 'John A. Smith',
      'location' => nil
    }

    employee = EssEmployee.new(api_data)

    refute employee.has_location?
    refute employee.has_resp_center_head?
    assert_nil employee.location
    assert_nil employee.resp_center_head
    assert_nil employee.resp_center_display_name
    assert_nil employee.resp_center_full_name
  end

  def test_has_resp_center_head_returns_correct_value
    employee = EssEmployee.new
    refute employee.has_resp_center_head?

    location = EssLocation.new(
      resp_center_head: EssResponsibilityCenterHead.new(
        code: 'TEST',
        short_name: 'TEST',
        name: 'Test Department'
      )
    )
    employee.location = location
    assert employee.has_resp_center_head?
  end

  def test_resp_center_helper_methods
    resp_center = EssResponsibilityCenterHead.new(
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator John A. Alpha'
    )
    location = EssLocation.new(resp_center_head: resp_center)
    employee = EssEmployee.new(location: location)

    assert_equal 'SEN PARKER', employee.resp_center_display_name
    assert_equal 'Senator John A. Alpha', employee.resp_center_full_name

    employee.location = nil
    assert_nil employee.resp_center_display_name
    assert_nil employee.resp_center_full_name
  end

  def test_to_hash_includes_resp_center_head
    resp_center = EssResponsibilityCenterHead.new(
      active: true,
      code: 'PARKER',
      short_name: 'SEN PARKER',
      name: 'Senator John A. Alpha',
      affiliate_code: 'MAJ'
    )
    location = EssLocation.new(
      loc_id: 'D21001-W',
      code: 'D21001',
      resp_center_head: resp_center
    )
    employee = EssEmployee.new(
      employee_id: 12345,
      first_name: 'John',
      last_name: 'Smith',
      full_name: 'John A. Smith',
      location: location
    )

    hash = employee.to_hash

    assert_not_nil hash[:location]
    assert_kind_of Hash, hash[:location]
    assert_not_nil hash[:location][:resp_center_head]
    assert_kind_of Hash, hash[:location][:resp_center_head]
    assert hash[:location][:resp_center_head][:active]
    assert_equal 'PARKER', hash[:location][:resp_center_head][:code]
    assert_equal 'SEN PARKER', hash[:location][:resp_center_head][:short_name]
  end
end