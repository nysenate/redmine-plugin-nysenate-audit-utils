# frozen_string_literal: true

require_relative '../test_helper'

module NysenateAuditUtils::Reporting
  class BusinessDayHelperTest < ActiveSupport::TestCase
    include NysenateAuditUtils::Reporting::BusinessDayHelper

    # Test previous_business_day for each day of the week
    test 'previous_business_day on Tuesday returns Monday' do
      tuesday = Date.new(2025, 10, 7) # October 7, 2025 is a Tuesday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(tuesday)
      assert_equal Date.new(2025, 10, 6), result # Monday
    end

    test 'previous_business_day on Monday returns previous Friday' do
      monday = Date.new(2025, 10, 6) # October 6, 2025 is a Monday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(monday)
      assert_equal Date.new(2025, 10, 3), result # Friday
    end

    test 'previous_business_day on Wednesday returns Tuesday' do
      wednesday = Date.new(2025, 10, 8) # October 8, 2025 is a Wednesday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(wednesday)
      assert_equal Date.new(2025, 10, 7), result # Tuesday
    end

    test 'previous_business_day on Thursday returns Wednesday' do
      thursday = Date.new(2025, 10, 9) # October 9, 2025 is a Thursday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(thursday)
      assert_equal Date.new(2025, 10, 8), result # Wednesday
    end

    test 'previous_business_day on Friday returns Thursday' do
      friday = Date.new(2025, 10, 10) # October 10, 2025 is a Friday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(friday)
      assert_equal Date.new(2025, 10, 9), result # Thursday
    end

    test 'previous_business_day on Saturday returns Friday' do
      saturday = Date.new(2025, 10, 11) # October 11, 2025 is a Saturday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(saturday)
      assert_equal Date.new(2025, 10, 10), result # Friday
    end

    test 'previous_business_day on Sunday returns Friday' do
      sunday = Date.new(2025, 10, 12) # October 12, 2025 is a Sunday
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(sunday)
      assert_equal Date.new(2025, 10, 10), result # Friday (2 days back)
    end

    # Test query_start_date for regular days
    test 'query_start_date on Tuesday returns Monday at 12:00 AM' do
      tuesday = Date.new(2025, 10, 7)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(tuesday)

      assert_equal Date.new(2025, 10, 6), result.to_date
      assert_equal 0, result.hour
      assert_equal 0, result.min
      assert_equal 0, result.sec
    end

    test 'query_start_date on Monday returns previous Friday at 12:00 AM' do
      monday = Date.new(2025, 10, 6)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(monday)

      assert_equal Date.new(2025, 10, 3), result.to_date
      assert_equal 0, result.hour
    end

    test 'query_start_date on Wednesday returns Tuesday at 12:00 AM' do
      wednesday = Date.new(2025, 10, 8)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(wednesday)

      assert_equal Date.new(2025, 10, 7), result.to_date
      assert_equal 0, result.hour
    end

    # Test first business day after January 1 logic
    test 'query_start_date on first Monday of year after Jan 1 returns 5 business days prior' do
      # January 1, 2025 is a Wednesday
      # First business day after is Thursday, Jan 2
      # But let's test Monday, Jan 6, 2025 (first Monday)
      monday_jan_6 = Date.new(2025, 1, 6)
      Time.zone = 'America/New_York'

      # This should NOT trigger the special Jan 1 logic since the first business day is Jan 2
      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(monday_jan_6)

      # Should just be previous Friday
      assert_equal Date.new(2025, 1, 3), result.to_date
    end

    test 'query_start_date on first business day after Jan 1 (Thursday) returns 5 calendar days prior' do
      # January 1, 2025 is a Wednesday
      # January 2, 2025 is a Thursday and is the first business day after Jan 1
      thursday_jan_2 = Date.new(2025, 1, 2)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(thursday_jan_2)

      # 5 calendar days before Jan 2 is Dec 28, 2024
      assert_equal Date.new(2024, 12, 28), result.to_date
    end

    test 'query_start_date when Jan 1 is Friday, first business day is Monday Jan 4' do
      # January 1, 2027 is a Friday
      # First business day after is Monday, January 4, 2027
      monday_jan_4 = Date.new(2027, 1, 4)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(monday_jan_4)

      # 5 calendar days before Jan 4, 2027 is Dec 30, 2026
      assert_equal Date.new(2026, 12, 30), result.to_date
    end

    test 'query_start_date when Jan 1 is Monday, first business day after is Jan 2' do
      # January 1, 2024 was a Monday
      # The first business day AFTER Jan 1 is Tuesday, Jan 2 (excluding Jan 1 itself)
      tuesday_jan_2 = Date.new(2024, 1, 2)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(tuesday_jan_2)

      # 5 calendar days before Jan 2, 2024 is Dec 28, 2023
      assert_equal Date.new(2023, 12, 28), result.to_date
    end

    # Test year boundary edge case
    test 'query_start_date handles year boundary correctly' do
      # December 31, 2024 is a Tuesday
      tuesday_dec_31 = Date.new(2024, 12, 31)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(tuesday_dec_31)

      # Should return Monday, Dec 30, 2024
      assert_equal Date.new(2024, 12, 30), result.to_date
    end

    # Test leap year edge case
    test 'previous_business_day handles leap year correctly' do
      # March 1, 2024 (leap year) on a Friday
      friday_mar_1 = Date.new(2024, 3, 1)

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day(friday_mar_1)

      # Should return Thursday, Feb 29, 2024 (leap day)
      assert_equal Date.new(2024, 2, 29), result
    end

    # Test that query_start_date works with Time and DateTime objects
    test 'query_start_date accepts Time object' do
      tuesday_time = Time.zone.parse('2025-10-07 15:30:00')
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(tuesday_time)

      assert_equal Date.new(2025, 10, 6), result.to_date
    end

    test 'query_start_date accepts DateTime object' do
      tuesday_datetime = DateTime.new(2025, 10, 7, 15, 30, 0)
      Time.zone = 'America/New_York'

      result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date(tuesday_datetime)

      assert_equal Date.new(2025, 10, 6), result.to_date
    end

    # Test default parameter (uses current date)
    test 'query_start_date uses current date when no parameter given' do
      Time.zone = 'America/New_York'
      travel_to Time.zone.parse('2025-10-07 15:30:00') do # Tuesday
        result = NysenateAuditUtils::Reporting::BusinessDayHelper.query_start_date

        assert_equal Date.new(2025, 10, 6), result.to_date # Monday
      end
    end

    test 'previous_business_day uses current date when no parameter given' do
      travel_to Time.zone.local(2025, 10, 7) do # Tuesday
        result = NysenateAuditUtils::Reporting::BusinessDayHelper.previous_business_day

        assert_equal Date.new(2025, 10, 6), result # Monday
      end
    end
  end
end
