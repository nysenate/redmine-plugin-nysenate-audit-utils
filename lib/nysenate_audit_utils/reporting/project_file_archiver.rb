# frozen_string_literal: true

require 'stringio'

module NysenateAuditUtils
  module Reporting
    class ProjectFileArchiver
      def self.archive(project:, filename:, content:, content_type:, description: nil)
        unless project.module_enabled?(:files)
          Rails.logger.warn(
            "[nysenate_audit_utils] Skipping report archive: " \
            "project '#{project.identifier}' does not have the Files module enabled"
          )
          return nil
        end

        attachment = Attachment.new(
          file: StringIO.new(content),
          filename: filename,
          content_type: content_type,
          author: User.anonymous,
          description: description.to_s[0, 255]
        )
        attachment.container = project

        if attachment.save
          Rails.logger.info(
            "[nysenate_audit_utils] Archived report '#{filename}' to project " \
            "'#{project.identifier}' Files (attachment ##{attachment.id})"
          )
          attachment
        else
          Rails.logger.warn(
            "[nysenate_audit_utils] Failed to archive report '#{filename}' to " \
            "project '#{project.identifier}': #{attachment.errors.full_messages.join('; ')}"
          )
          nil
        end
      rescue StandardError => e
        Rails.logger.warn(
          "[nysenate_audit_utils] Exception while archiving report '#{filename}' to " \
          "project '#{project.identifier}': #{e.class}: #{e.message}"
        )
        nil
      end
    end
  end
end
