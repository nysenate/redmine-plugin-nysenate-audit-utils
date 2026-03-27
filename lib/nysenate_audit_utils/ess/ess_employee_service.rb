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
          # Translate 0-based offset to ESS API's 1-based offset
          # Plugin uses: offset=0 (records 0-19), offset=20 (records 20-39)
          # ESS API uses: offset=0 (positions 1-20), offset=21 (positions 21-40)
          params[:offset] = translate_offset_to_ess(validate_offset(offset))
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

        # Translate 0-based offset to ESS API's 1-based offset
        # ESS API uses 1-indexed positions where offset=0 is special (positions 1-20),
        # and offset=N means "start at position N" for N>0
        def translate_offset_to_ess(offset)
          offset == 0 ? 0 : offset + 1
        end

        def api_client
          NysenateAuditUtils::Ess::EssApiClient.new
        end
      end
    end
  end
end