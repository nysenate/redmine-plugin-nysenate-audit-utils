module NysenateAuditUtils
  module Ess
    class EssEmployeeService
      class << self
        def search(term = '', limit: 20, offset: 0)
          params = build_search_params(term, limit, offset)

          response = api_client.get('/api/v1/bachelp/employee/search', params)
          return [] unless response && response['success']

          employees = response['result'] || []
          employees.map { |employee_data| EssEmployee.new(employee_data) }
        end

        def find_by_id(employee_id)
          return nil unless employee_id.present?

          response = api_client.get("/api/v1/bachelp/employee/#{employee_id}")
          return nil unless response && response['success']

          employee_data = response['employee']
          return nil unless employee_data

          EssEmployee.new(employee_data)
        end

        private

        def build_search_params(term, limit, offset)
          params = {}
          params[:term] = term if term.present?
          params[:limit] = validate_limit(limit)
          params[:offset] = validate_offset(offset)
          params
        end

        def validate_limit(limit)
          limit = limit.to_i
          return 20 if limit <= 0
          return 1000 if limit > 1000
          limit
        end

        def validate_offset(offset)
          offset = offset.to_i
          offset < 0 ? 0 : offset
        end

        def api_client
          NysenateAuditUtils::Ess::EssApiClient.new
        end
      end
    end
  end
end