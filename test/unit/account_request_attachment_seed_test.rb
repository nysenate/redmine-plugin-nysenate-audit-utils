# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# Proves the Phase 2 seeding contract: a container-less attachment created by the
# AccountRequestsController is attached to the issue by core's save_attachments
# (the path core IssuesController#create takes) when its token rides the form.
class AccountRequestAttachmentSeedTest < NysenateAuditUtilsTestCase
  fixtures :users, :projects, :trackers, :projects_trackers, :issue_statuses, :enumerations

  def test_seeded_container_less_attachment_is_attached_via_its_token
    User.current = User.find(1)

    # The controller builds this: a container-less (tokenable) CSV attachment.
    seeded = Attachment.new(
      file: StringIO.new("a,b\n1,2\n"),
      filename: 'daily_report_20260625.csv',
      content_type: 'text/csv',
      author: User.current
    )
    assert seeded.save, seeded.errors.full_messages.join('; ')
    assert_nil seeded.container
    assert_match(/\A\d+\.[0-9a-f]+\z/, seeded.token)

    issue = Issue.new(project_id: 1, tracker_id: 1, author_id: 1, subject: 'Account request')

    # Mirror core IssuesController#create: save_attachments(params[:attachments]).
    issue.save_attachments('daily_report' => { 'token' => seeded.token })
    assert issue.save, issue.errors.full_messages.join('; ')

    assert_includes issue.reload.attachments.map(&:id), seeded.id
    assert_equal issue.id, seeded.reload.container_id
  end
end
