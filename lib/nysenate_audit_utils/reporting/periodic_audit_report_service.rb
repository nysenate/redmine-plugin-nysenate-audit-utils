# frozen_string_literal: true

module NysenateAuditUtils
  module Reporting
    # Builds the Quarterly / Annual audit report: closed tickets for a single
    # target system (SFMS or SFS) over an audit window. Feeds the SFMS Quarterly
    # Audit and the SFS Annual (Account & Roles Validation) Audit.
    #
    # Output mirrors Kim's spreadsheet columns rather than the Weekly report:
    #   RequestType, FullName, Userid, Office, EntryDate, CompletedDate,
    #   BacNumber, SenDevNumber (ticket #), Description (subject).
    class PeriodicAuditReportService
      # System selector => request-code prefix used to resolve the configured
      # target-system value(s) to filter on.
      SYSTEM_PREFIXES = {
        sfms: 'USR',
        sfs: 'SFS'
      }.freeze

      attr_reader :system, :from_date, :to_date, :errors, :project, :target_systems

      # @param project [Project]
      # @param system [Symbol, String] :sfms or :sfs
      # @param from_date [Time, Date] start of the audit window (inclusive)
      # @param to_date [Time, Date] end of the audit window (inclusive)
      def initialize(project:, system: :sfms, from_date: nil, to_date: nil)
        @project = project
        @system = system.to_sym == :sfs ? :sfs : :sfms

        if from_date && to_date
          @from_date = from_date
          @to_date = to_date
        else
          window = self.class.default_window(@system)
          @from_date = window[:from]
          @to_date = window[:to]
        end

        @target_systems = self.class.target_systems_for(@system)
        @errors = []
      end

      # @return [Array<Hash>, nil] report rows or nil on error
      def generate
        build_report_data
      rescue StandardError => e
        @errors << "Report generation failed: #{e.message}"
        Rails.logger.error("PeriodicAuditReportService error: #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      def success?
        @errors.empty?
      end

      # Resolve the configured target-system value(s) whose request-code prefix
      # matches the selected system (e.g. :sfms => ["Oracle / SFMS"]).
      # @param system [Symbol] :sfms or :sfs
      # @return [Array<String>]
      def self.target_systems_for(system)
        prefix = SYSTEM_PREFIXES[system.to_sym]
        return [] unless prefix

        settings = Setting.plugin_nysenate_audit_utils || {}
        prefixes = settings['request_code_system_prefixes'] || {}
        prefixes.select { |_value, code| code == prefix }.keys
      end

      # The most recently completed audit window for a system.
      #   SFMS: the latest closed offset-quarter (ending Jan 31/Apr 30/Jul 31/Oct 31).
      #   SFS:  the trailing year ending today, inclusive both ends. An end date of
      #         6/11 yields a start of 6/12 the previous year.
      # @return [Hash] { from:, to: }
      def self.default_window(system)
        if system.to_sym == :sfs
          to = Date.current
          { from: sfs_start_for(to).to_time, to: to.to_time.end_of_day }
        else
          recent_sfms_quarters(1).first
        end
      end

      # Inclusive one-year-prior start for an SFS end date (end - 1 year + 1 day).
      # @param end_date [Date]
      # @return [Date]
      def self.sfs_start_for(end_date)
        end_date - 1.year + 1.day
      end

      # Recent SFMS offset-quarter windows, most recent (completed) first.
      # Windows are calendar quarters shifted back one month:
      #   Nov 1–Jan 31, Feb 1–Apr 30, May 1–Jul 31, Aug 1–Oct 31.
      # @param count [Integer] number of windows to return
      # @return [Array<Hash>] [{ label:, from:, to: }, ...]
      def self.recent_sfms_quarters(count = 8)
        # Audit windows end on the last day of Jan/Apr/Jul/Oct. Find the most
        # recent such month-end that has already passed.
        today = Date.current
        end_months = [1, 4, 7, 10]
        anchor = today.beginning_of_month
        # Step the anchor back to the latest end-month whose month-end < today.
        anchor = anchor.prev_month until end_months.include?(anchor.month) && anchor.end_of_month < today

        (0...count).map do |i|
          last_month = anchor.prev_month(3 * i)
          first_day = last_month.prev_month(2).beginning_of_month
          last_day  = last_month.end_of_month
          {
            label: "#{first_day.strftime('%b %Y')} – #{last_day.strftime('%b %Y')}",
            from: first_day.to_time,
            to: last_day.to_time.end_of_day
          }
        end
      end

      private

      def build_report_data
        cfg = NysenateAuditUtils::CustomFieldConfiguration
        user_name_field_id    = cfg.get_field_id('user_name_field_id')
        user_uid_field_id     = cfg.get_field_id('user_uid_field_id')
        user_location_field_id = cfg.get_field_id('user_location_field_id')
        account_action_field_id = cfg.account_action_field_id
        target_system_field_id  = cfg.target_system_field_id
        bac_number_field_id     = cfg.bac_number_field_id

        unless target_system_field_id
          @errors << 'Target System custom field is not configured'
          return []
        end

        if @target_systems.empty?
          @errors << "No target system is mapped to the #{@system.to_s.upcase} request-code prefix"
          return []
        end

        request_code_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new

        # Closed issues in the window whose Target System custom value is one of
        # the systems for the selected prefix (USR* for SFMS, SFS* for SFS).
        matching_issue_ids = CustomValue
          .where(customized_type: 'Issue', custom_field_id: target_system_field_id, value: @target_systems)
          .select(:customized_id)

        issues = Issue
          .where(project_id: @project.id)
          .where(id: matching_issue_ids)
          .where(closed_on: @from_date..@to_date)
          .joins(:status)
          .where(issue_statuses: { is_closed: true })
          .includes(:status, :custom_values)
          .order(closed_on: :desc)

        issues.map do |issue|
          account_action = account_action_field_id ? get_custom_field_value(issue, account_action_field_id) : nil
          target_system  = get_custom_field_value(issue, target_system_field_id)
          request_code   = request_code_mapper.get_request_code(account_action, target_system)

          {
            request_code: request_code,
            user_name: user_name_field_id ? get_custom_field_value(issue, user_name_field_id) : nil,
            user_uid: user_uid_field_id ? get_custom_field_value(issue, user_uid_field_id) : nil,
            office: user_location_field_id ? get_custom_field_value(issue, user_location_field_id) : nil,
            created_on: issue.created_on,
            closed_on: issue.closed_on,
            bac_number: bac_number_field_id ? get_custom_field_value(issue, bac_number_field_id) : nil,
            issue_id: issue.id,
            subject: issue.subject
          }
        end
      end

      def get_custom_field_value(issue, field_id)
        custom_value = issue.custom_values.find { |cv| cv.custom_field_id == field_id }
        custom_value&.value
      end
    end
  end
end
