# frozen_string_literal: true

require_relative '../test_helper'

class ProjectFileArchiverTest < NysenateAuditUtilsTestCase
  fixtures :projects, :users, :enabled_modules

  def setup
    super
    @project = Project.find(1)
    @project.enabled_modules.where(name: 'files').destroy_all
  end

  def enable_files_module
    @project.enabled_modules.create!(name: 'files')
    @project.reload
  end

  def archive(**overrides)
    NysenateAuditUtils::Reporting::ProjectFileArchiver.archive(
      **{
        project: @project,
        filename: 'report.csv',
        content: "a,b,c\n1,2,3\n",
        content_type: 'text/csv',
        description: 'Test report'
      }.merge(overrides)
    )
  end

  def test_returns_nil_and_logs_warning_when_files_module_disabled
    warnings = capture_logger_warnings { @result = archive }

    assert_nil @result
    assert_empty @project.attachments.where(filename: 'report.csv')
    assert(warnings.any? { |m| m.include?('does not have the Files module enabled') },
           "Expected a warning about disabled Files module, got: #{warnings.inspect}")
  end

  def test_creates_attachment_on_project_when_files_module_enabled
    enable_files_module
    attachment = archive

    assert_kind_of Attachment, attachment
    assert_equal @project, attachment.container
    assert_equal 'report.csv', attachment.filename
    assert_equal 'text/csv', attachment.content_type
    assert_equal 'Test report', attachment.description
    assert_equal User.anonymous, attachment.author
    assert_equal "a,b,c\n1,2,3\n", File.read(attachment.diskfile)
  end

  def test_appears_in_project_files_listing
    enable_files_module
    attachment = archive

    assert_includes @project.attachments.reload, attachment
  end

  def test_truncates_description_to_255_chars
    enable_files_module
    attachment = archive(description: 'x' * 500)

    assert_equal 255, attachment.description.length
  end

  def test_nil_description_is_allowed
    enable_files_module
    attachment = archive(description: nil)

    assert_kind_of Attachment, attachment
    assert_equal '', attachment.description
  end

  def test_returns_nil_and_logs_warning_when_save_fails
    enable_files_module
    Attachment.any_instance.stubs(:save).returns(false)
    Attachment.any_instance.stubs(:errors).returns(
      ActiveModel::Errors.new(Attachment.new).tap { |e| e.add(:base, 'forced failure') }
    )

    warnings = capture_logger_warnings { @result = archive }

    assert_nil @result
    assert(warnings.any? { |m| m.include?('Failed to archive report') },
           "Expected save-failure warning, got: #{warnings.inspect}")
  end

  def test_rescues_exception_during_save
    enable_files_module
    Attachment.any_instance.stubs(:save).raises(StandardError, 'boom')

    warnings = capture_logger_warnings { @result = archive }

    assert_nil @result
    assert(warnings.any? { |m| m.include?('Exception while archiving report') && m.include?('boom') },
           "Expected exception warning, got: #{warnings.inspect}")
  end

  private

  def capture_logger_warnings
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = Logger.new(io)
    yield
    io.string.each_line.select { |l| l.include?('WARN') }.map(&:strip)
  ensure
    Rails.logger = original_logger
  end
end
