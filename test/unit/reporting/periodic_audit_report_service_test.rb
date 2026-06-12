# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NysenateAuditUtils
  module Reporting
    class PeriodicAuditReportServiceTest < ActiveSupport::TestCase
      fixtures :issues, :issue_statuses, :projects, :trackers, :custom_fields, :custom_values

      def setup
        @project = Project.find(1)

        @target_system_field = IssueCustomField.create!(
          name: 'Target System', field_format: 'list', is_for_all: true,
          possible_values: ['Oracle / SFMS', 'SFS', 'AIX'], trackers: Tracker.all
        )
        @account_action_field = IssueCustomField.create!(
          name: 'Account Action', field_format: 'list', is_for_all: true,
          possible_values: %w[Add Delete], trackers: Tracker.all
        )
        @bac_field = IssueCustomField.create!(
          name: 'BAC #', field_format: 'string', is_for_all: true, trackers: Tracker.all
        )

        Setting.plugin_nysenate_audit_utils = {
          'target_system_field_id'  => @target_system_field.id.to_s,
          'account_action_field_id' => @account_action_field.id.to_s,
          'bac_number_field_id'     => @bac_field.id.to_s,
          'request_code_system_prefixes' => { 'Oracle / SFMS' => 'USR', 'SFS' => 'SFS', 'AIX' => 'AIX' },
          'request_code_action_suffixes' => { 'Add' => 'A', 'Delete' => 'I' }
        }
      end

      def teardown
        Setting.plugin_nysenate_audit_utils = {}
        [@target_system_field, @account_action_field, @bac_field].each { |f| f&.destroy }
      end

      def make_closed_issue(target_system:, closed_on:, action: 'Add', bac: nil)
        issue = Issue.create!(project: @project, tracker_id: 1, author_id: 1,
                              status_id: 5, subject: "#{target_system} ticket")
        Issue.where(id: issue.id).update_all(created_on: closed_on - 1.day,
                                             updated_on: closed_on, closed_on: closed_on)
        issue.reload
        values = { @target_system_field.id => target_system, @account_action_field.id => action }
        values[@bac_field.id] = bac if bac
        issue.custom_field_values = values
        issue.save!
        issue
      end

      # --- window math (pure) -------------------------------------------------

      test "recent_sfms_quarters returns offset quarters ending Jan/Apr/Jul/Oct" do
        travel_to Time.zone.parse('2026-06-11 12:00:00') do
          quarters = PeriodicAuditReportService.recent_sfms_quarters(2)

          assert_equal Date.new(2026, 2, 1),  quarters[0][:from].to_date
          assert_equal Date.new(2026, 4, 30), quarters[0][:to].to_date
          assert_equal Date.new(2025, 11, 1), quarters[1][:from].to_date
          assert_equal Date.new(2026, 1, 31), quarters[1][:to].to_date
        end
      end

      test "sfms default window is the most recently completed offset quarter" do
        travel_to Time.zone.parse('2026-06-11 12:00:00') do
          service = PeriodicAuditReportService.new(project: @project, system: :sfms)
          assert_equal Date.new(2026, 2, 1),  service.from_date.to_date
          assert_equal Date.new(2026, 4, 30), service.to_date.to_date
        end
      end

      test "sfs default window is the trailing inclusive year ending today" do
        travel_to Time.zone.parse('2026-06-11 12:00:00') do
          service = PeriodicAuditReportService.new(project: @project, system: :sfs)
          # Inclusive both ends: 6/12/2025 through 6/11/2026.
          assert_equal Date.new(2025, 6, 12), service.from_date.to_date
          assert_equal Date.new(2026, 6, 11), service.to_date.to_date
        end
      end

      test "sfs_start_for is one year prior plus one day (inclusive)" do
        assert_equal Date.new(2025, 6, 12),
                     PeriodicAuditReportService.sfs_start_for(Date.new(2026, 6, 11))
      end

      test "target_systems_for resolves configured prefixes" do
        assert_equal ['Oracle / SFMS'], PeriodicAuditReportService.target_systems_for(:sfms)
        assert_equal ['SFS'], PeriodicAuditReportService.target_systems_for(:sfs)
      end

      # --- filtering ----------------------------------------------------------

      test "sfms report includes only Oracle/SFMS closed tickets in window" do
        sfms = make_closed_issue(target_system: 'Oracle / SFMS', closed_on: 3.days.ago)
        sfs  = make_closed_issue(target_system: 'SFS', closed_on: 3.days.ago)
        aix  = make_closed_issue(target_system: 'AIX', closed_on: 3.days.ago)

        service = PeriodicAuditReportService.new(project: @project, system: :sfms,
                                                 from_date: 1.week.ago, to_date: Time.zone.now)
        ids = service.generate.map { |r| r[:issue_id] }

        assert service.success?
        assert_includes ids, sfms.id
        assert_not_includes ids, sfs.id
        assert_not_includes ids, aix.id
      end

      test "report excludes tickets closed outside the window" do
        in_window  = make_closed_issue(target_system: 'SFS', closed_on: 3.days.ago)
        out_window = make_closed_issue(target_system: 'SFS', closed_on: 3.weeks.ago)

        service = PeriodicAuditReportService.new(project: @project, system: :sfs,
                                                 from_date: 1.week.ago, to_date: Time.zone.now)
        ids = service.generate.map { |r| r[:issue_id] }

        assert_includes ids, in_window.id
        assert_not_includes ids, out_window.id
      end

      test "row maps request_code, bac_number and ticket id" do
        issue = make_closed_issue(target_system: 'Oracle / SFMS', action: 'Delete',
                                  closed_on: 2.days.ago, bac: '67419')

        service = PeriodicAuditReportService.new(project: @project, system: :sfms,
                                                 from_date: 1.week.ago, to_date: Time.zone.now)
        row = service.generate.find { |r| r[:issue_id] == issue.id }

        assert_equal 'USRI', row[:request_code]
        assert_equal '67419', row[:bac_number]
        assert_equal issue.id, row[:issue_id]
      end

      test "csv uses the legacy spreadsheet headers" do
        issue = make_closed_issue(target_system: 'Oracle / SFMS', closed_on: 2.days.ago, bac: '67419')
        service = PeriodicAuditReportService.new(project: @project, system: :sfms,
                                                 from_date: 1.week.ago, to_date: Time.zone.now)
        data = service.generate
        csv = CsvGenerator.generate_periodic_csv(data)
        rows = CSV.parse(csv)

        # No metadata preamble: the header is the very first row.
        assert_equal %w[RequestType FullName Userid Office EntryDate CompletedDate
                        BacNumber SenDevNumber GeneralFormInfoID Program Description], rows.first
        ticket_row = rows.find { |r| r[7].to_s == issue.id.to_s }
        assert_equal '67419', ticket_row[6]
        assert_nil ticket_row[8]
        assert_equal 'SFMS', ticket_row[9]
      end
    end
  end
end
