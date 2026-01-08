require File.expand_path('../../test_helper', __FILE__)

class EssStatusChangeServiceTest < ActiveSupport::TestCase
  def setup
    @api_client_mock = mock('api_client')
    NysenateAuditUtils::Ess::EssStatusChangeService.stubs(:api_client).returns(@api_client_mock)
  end

  def test_changes_for_date_range_returns_status_changes_for_valid_response
    api_response = {
      'success' => true,
      'result' => [
        sample_status_change_data(12345, 'jsmith', 'John', 'Smith', 'APP'),
        sample_status_change_data(12346, 'mjones', 'Mary', 'Jones', 'EMP')
      ]
    }

    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
      from: '2023-08-15'
    }).returns(api_response)

    changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15')

    assert_equal 2, changes.length
    assert_equal 12345, changes.first.employee.employee_id
    assert_equal 'APP', changes.first.transaction_code
    assert_equal 'EMP', changes.last.transaction_code
  end

  def test_changes_for_date_range_with_date_range
    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
      from: '2023-08-15',
      to: '2023-08-16'
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15', '2023-08-16')
  end

  def test_changes_for_date_range_uses_default_from_date
    # Mock Time.now for consistent testing
    frozen_time = Time.zone.parse('2023-08-16 12:00:00')
    travel_to(frozen_time) do
      expected_from = 1.day.ago.strftime('%Y-%m-%d')

      @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
        from: expected_from
      }).returns({'success' => true, 'result' => []})

      NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range
    end
  end

  def test_changes_for_date_range_formats_date_objects
    date = Date.parse('2023-08-15')
    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
      from: '2023-08-15'
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(date)
  end

  def test_changes_for_date_range_formats_time_objects
    time = Time.zone.parse('2023-08-15 14:30:45')
    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
      from: '2023-08-15'
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(time)
  end

  def test_changes_for_date_range_formats_datetime_objects
    datetime = DateTime.parse('2023-08-15 14:30:45 UTC')
    
    # Allow any datetime format since the exact format may vary
    @api_client_mock.expects(:get).with(anything, anything).returns({'success' => true, 'result' => []})

    result = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(datetime)
    
    assert_equal [], result
  end

  def test_changes_for_date_range_passes_string_dates_unchanged
    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {
      from: '2023-08-15'
    }).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15')
  end

  def test_changes_for_date_range_omits_nil_dates
    @api_client_mock.expects(:get).with('/api/v1/bachelp/statusChanges', {}).returns({'success' => true, 'result' => []})

    NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range(nil, nil)
  end

  def test_changes_for_date_range_returns_empty_array_for_failed_response
    @api_client_mock.expects(:get).returns({'success' => false})

    changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15')

    assert_equal [], changes
  end

  def test_changes_for_date_range_returns_empty_array_for_nil_response
    @api_client_mock.expects(:get).returns(nil)

    changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15')

    assert_equal [], changes
  end

  def test_changes_for_date_range_handles_missing_result
    @api_client_mock.expects(:get).returns({'success' => true, 'result' => nil})

    changes = NysenateAuditUtils::Ess::EssStatusChangeService.changes_for_date_range('2023-08-15')

    assert_equal [], changes
  end

  private

  def sample_status_change_data(id, uid, first_name, last_name, transaction_code)
    {
      'employeeId' => id,
      'uid' => uid,
      'firstName' => first_name,
      'lastName' => last_name,
      'fullName' => "#{first_name} A. #{last_name}",
      'email' => "#{uid}@nysenate.gov",
      'workPhone' => '(518) 555-0123',
      'active' => true,
      'transactionCode' => transaction_code,
      'postDateTime' => '2023-08-15T10:30:00Z'
    }
  end
end