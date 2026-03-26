module NysenateAuditUtils
  module Autofill
    class Hooks < Redmine::Hook::ViewListener

      render_on :view_layouts_base_html_head, partial: 'autofill/assets'

      def view_issues_form_details_bottom(context = {})
        Rails.logger.debug "BachelpAutofill Hook: view_issues_form_details_bottom called"
        issue = context[:issue]

        if issue.nil?
          Rails.logger.debug "BachelpAutofill Hook: No issue in context"
          return ''
        end

        if issue.tracker.nil?
          Rails.logger.debug "BachelpAutofill Hook: Issue has no tracker"
          return ''
        end

        if issue.project.nil?
          Rails.logger.debug "BachelpAutofill Hook: Issue has no project"
          return ''
        end

        Rails.logger.debug "BachelpAutofill Hook: Issue tracker: #{issue.tracker.name}"

        # Check if module is enabled for this project
        unless issue.project.module_enabled?(:audit_utils)
          Rails.logger.debug "BachelpAutofill Hook: User Autofill module not enabled for project"
          return ''
        end

        # Check if user has permission for this project
        unless User.current.allowed_to?(:use_user_autofill, issue.project)
          Rails.logger.debug "BachelpAutofill Hook: User lacks use_user_autofill permission for project"
          return ''
        end

        if has_user_fields?(issue.tracker)
          Rails.logger.debug "BachelpAutofill Hook: Tracker has user fields, rendering widget"
          return render_user_search_widget(context)
        else
          Rails.logger.debug "BachelpAutofill Hook: Tracker has no user fields"
          return ''
        end
      end

      private

      def has_user_fields?(tracker)
        return false unless tracker

        field_ids = NysenateAuditUtils::CustomFieldConfiguration.autofill_field_ids.values
        tracker_field_ids = tracker.custom_fields.pluck(:id)

        Rails.logger.debug "BachelpAutofill Hook: Expected field IDs: #{field_ids.inspect}"
        Rails.logger.debug "BachelpAutofill Hook: Tracker field IDs: #{tracker_field_ids.inspect}"

        # Check if any of the configured user fields are available for this tracker
        result = (field_ids & tracker_field_ids).any?
        Rails.logger.debug "BachelpAutofill Hook: has_user_fields result: #{result}"
        result
      end

      def render_user_search_widget(context)
        context[:controller].render_to_string(
          partial: 'user_search/search_widget',
          locals: { issue: context[:issue] }
        )
      end
    end
  end
end