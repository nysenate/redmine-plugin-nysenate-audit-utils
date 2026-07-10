# frozen_string_literal: true

module NysenateAuditUtils
  # Wires the daily report's "create removal ticket" button to a related issue.
  #
  # The button seeds `related_issue_id` (the granting ticket, i.e. the one linked
  # by "View last ticket") into the new-issue form. This listener:
  #   * renders a visible, overridable "Related issue" chooser inside the form, and
  #   * creates the IssueRelation once the new ticket is saved.
  #
  # It never blocks ticket creation: a blank, invalid, or non-visible id (or a
  # relation save error) only sets a flash warning.
  class RelationPrefillHook < Redmine::Hook::ViewListener
    # Render the related-issue field, but only on a new-issue form seeded with a
    # related_issue_id by the removal-ticket flow.
    def view_issues_form_details_bottom(context = {})
      controller = context[:controller]
      issue = context[:issue]
      return '' unless controller && issue&.new_record?

      params = controller.params
      related_id = params[:related_issue_id].presence
      return '' if related_id.blank?

      controller.send(
        :render_to_string,
        partial: 'account_requests/related_issue_field',
        locals: {
          related_issue: Issue.visible.find_by(id: related_id),
          related_issue_id: related_id,
          relation_type: params[:related_relation_type].presence || IssueRelation::TYPE_RELATES
        }
      )
    end

    # After the new issue saves, link it to the chosen granting ticket.
    def controller_issues_new_after_save(context = {})
      controller = context[:controller]
      issue = context[:issue]
      return unless controller && issue

      related_id = controller.params[:related_issue_id].presence
      return if related_id.blank?

      target = Issue.visible.find_by(id: related_id)
      relation_type = controller.params[:related_relation_type].presence || IssueRelation::TYPE_RELATES

      if target &&
         IssueRelation.new(issue_from: issue, issue_to: target, relation_type: relation_type).save
        return
      end

      controller.send(:flash)[:warning] =
        I18n.t(:warning_related_issue_not_linked, id: related_id)
    end
  end
end
