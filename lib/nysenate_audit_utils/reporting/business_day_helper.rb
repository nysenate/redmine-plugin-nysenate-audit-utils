# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Helper module for business day calculations used in report date range queries.
    #
    # Business rules:
    # - Tuesday-Friday: Previous day at 12:00 AM
    # - Monday: Previous Friday at 12:00 AM
    # - First business day after January 1: Five business days prior at 12:00 AM
    module BusinessDayHelper
      class << self
        # Returns the previous business day from the given date.
        # Does not account for holidays, only weekends.
        #
        # @param date [Date, Time, DateTime] The reference date
        # @return [Date] The previous business day
        def previous_business_day(date = Date.current)
          date = date.to_date

          case date.wday
          when 0 # Sunday -> Friday
            date - 2.days
          when 1 # Monday -> Friday
            date - 3.days
          else # Tuesday-Saturday -> previous day
            date - 1.day
          end
        end

        # Calculates the query start date for reports based on business day rules.
        # Returns the date at beginning of day (12:00 AM) in the application time zone.
        #
        # Special case: On the first business day after January 1, returns 5 calendar days prior
        # to account for the extended weekend/holiday period.
        #
        # @param reference_date [Date, Time, DateTime] The date to calculate from (defaults to today)
        # @return [ActiveSupport::TimeWithZone] The query start date at 12:00 AM
        def query_start_date(reference_date = Date.current)
          reference_date = reference_date.to_date

          # Check if we're in the first business day after January 1
          if first_business_day_after_new_year?(reference_date)
            start_date = reference_date - 5.days
          else
            start_date = previous_business_day(reference_date)
          end

          # Return as beginning of day in the application time zone
          Time.zone.parse(start_date.to_s).beginning_of_day
        end

        private

        # Checks if the given date is the first business day after January 1.
        # "After" means strictly after - January 1 itself is excluded.
        #
        # @param date [Date] The date to check
        # @return [Boolean] True if this is the first business day after Jan 1
        def first_business_day_after_new_year?(date)
          # Not in first week of year
          return false unless date.month == 1 && date.day <= 7

          jan_1 = Date.new(date.year, 1, 1)

          # Find the first business day strictly AFTER Jan 1 (not including Jan 1)
          first_bday = jan_1 + 1.day
          first_bday += 1.day while first_bday.saturday? || first_bday.sunday?

          # Are we on that first business day?
          date == first_bday
        end
      end
    end
  end
end
