# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Single source of truth for audit-report artifact filenames.
    #
    # Every output path builds its filename from these stems so the naming
    # convention lives in exactly one place instead of being copy-pasted:
    #   * interactive "Export Excel" downloads (AuditReportsController)
    #   * copies archived to project Files (audit_reports.rake) — these append a
    #     generation timestamp to the stem for uniqueness
    #   * Excel attachments emailed to recipients (AuditReportsMailer)
    #   * the daily-report CSV seeded onto report-launched tickets
    #     (AccountRequestsController)
    #
    # A "stem" is the filename without extension and without the archive
    # timestamp. The datestamp reflects the report's parameters (not the day it
    # was generated), except for live "current"-state snapshots which are stamped
    # with today's date.
    module ReportFilenames
      module_function

      # Daily report. business_day mode names the single selected (end) date;
      # range mode names both ends of the explicit window.
      def daily_stem(from_date:, to_date:, mode: 'business_day')
        period = if mode == 'range'
                   "#{ymd(from_date)}_#{ymd(to_date)}"
                 else
                   ymd(to_date)
                 end
        "daily_report_#{period}"
      end

      # Weekly report always covers an explicit [from, to] window.
      def weekly_stem(from_date:, to_date:)
        "weekly_report_#{ymd(from_date)}_#{ymd(to_date)}"
      end

      # Monthly report for a single target system.
      def monthly_stem(target_system:, mode:, selected_year: nil, selected_month_num: nil)
        "monthly_report_#{target_system.parameterize}_" \
          "#{monthly_suffix(mode: mode, selected_year: selected_year, selected_month_num: selected_month_num)}"
      end

      # Monthly report aggregated across every target system.
      def all_systems_monthly_stem(mode:, selected_year: nil, selected_month_num: nil)
        "monthly_reports_all_systems_" \
          "#{monthly_suffix(mode: mode, selected_year: selected_year, selected_month_num: selected_month_num)}"
      end

      # The month/current suffix shared by the monthly reports. Current mode is a
      # live snapshot, so it is stamped with today's date; monthly mode names the
      # selected month as YYYYMM.
      def monthly_suffix(mode:, selected_year: nil, selected_month_num: nil)
        if mode == 'current'
          Date.current.strftime('%Y%m%d')
        else
          "#{selected_year}#{selected_month_num.to_s.rjust(2, '0')}"
        end
      end

      # Format a Date or Time as YYYYMMDD.
      def ymd(value)
        value.to_date.strftime('%Y%m%d')
      end
    end
  end
end
