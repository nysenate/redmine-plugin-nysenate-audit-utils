module NysenateAuditUtils
  module Ess
    class EssStatusChangeService
      class << self
        def changes_for_date_range(from_date = 1.day.ago, to_date = nil)
          params = build_params(from_date, to_date)

          response = api_client.get('/api/v1/bachelp/statusChanges', params)
          return [] unless response && response['success']

          changes = response['result'] || []
          changes.map { |change_data| EssStatusChange.new(change_data) }
        end

        private

        def build_params(from_date, to_date = nil)
          params = {}
          params[:from] = format_datetime(from_date) if from_date
          params[:to] = format_datetime(to_date) if to_date
          params
        end

        def format_datetime(datetime)
          case datetime
          when String
            datetime
          when Date
            # Format as ISO date (YYYY-MM-DD)
            datetime.strftime('%Y-%m-%d')
          when Time, DateTime
            # Format as ISO date (YYYY-MM-DD)
            datetime.strftime('%Y-%m-%d')
          else
            datetime.to_s
          end
        end

        def api_client
          NysenateAuditUtils::Ess::EssApiClient.new
        end
      end
    end
  end
end