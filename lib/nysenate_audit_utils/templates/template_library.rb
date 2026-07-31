# frozen_string_literal: true

module NysenateAuditUtils
  module Templates
    # Reads the template tickets kept in the configured "templates project" and
    # exposes them to the Daily Report plus-sign flow (feature #18835).
    #
    # A template is an *open* issue in the configured project whose subject
    # carries the MARKER. The subject splits on the MARKER into:
    #   * the menu LABEL (text before the marker, e.g. "SFSS:"), and
    #   * the SUBJECT TEMPLATE (text after the marker), which becomes the new
    #     ticket's subject once its `<Field Name>` tokens are interpolated.
    module TemplateLibrary
      MARKER = '<TEMPLATE>'

      module_function

      # @return [Project, nil] the configured templates project
      def project
        NysenateAuditUtils::CustomFieldConfiguration.templates_project
      end

      # @return [Boolean] whether a usable template list exists
      def available?
        project.present? && templates.any?
      end

      # Lightweight, view-ready list of the eligible templates.
      # @return [Array<Hash>] { id:, label:, subject_template: }, sorted by label
      def templates
        eligible_issues
          .map { |issue| entry_for(issue) }
          .sort_by { |e| e[:label].downcase }
      end

      # Resolve a template by id, but ONLY if it is one of the eligible
      # templates. This is the security gate: it stops an arbitrary issue id in
      # the URL from being copied onto a new ticket.
      # @param id [String, Integer]
      # @return [Issue, nil]
      def find(id)
        return nil if id.blank?

        eligible_issues.detect { |issue| issue.id == id.to_i }
      end

      # The Issue records eligible to act as templates: open, visible, in the
      # configured project, and carrying the MARKER in their subject.
      # @return [Array<Issue>]
      def eligible_issues
        proj = project
        return [] unless proj

        Issue.where(project_id: proj.id)
             .open
             .visible
             .where('subject LIKE ?', "%#{MARKER}%")
             .to_a
      end

      # Build the entry for one issue. `display` is the menu text (label plus the
      # subject template, e.g. "AIXI: Remove AIX access for <Account Holder Name>");
      # `label` and `subject_template` are kept for the split pieces.
      # @param issue [Issue]
      # @return [Hash]
      def entry_for(issue)
        label, _marker, after = issue.subject.partition(MARKER)
        label = label.strip.presence || issue.subject.strip
        subject_template = after.strip
        {
          id: issue.id,
          label: label,
          subject_template: subject_template,
          display: [label, subject_template].reject(&:blank?).join(' ')
        }
      end
    end
  end
end
