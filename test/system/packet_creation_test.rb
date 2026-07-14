# frozen_string_literal: true

require File.expand_path('../../system_test_helper', __FILE__)

# Browser end-to-end tests for Ticket Packet Creation.
#
# Two user-facing entry points are exercised:
#
#   1. Single-ticket packet -- the attachments_helper_patch injects a
#      "Create Packet" button (a.icon-package, method: :post) into the
#      attachments `.contextual` menu on the issue detail page. Clicking it
#      POSTs to packet_creation#create, which streams back
#      `packet_<id>.zip` (ticket PDF + attachments).
#
#   2. Bulk packet -- IssueContextMenuHook#view_issues_context_menu_end adds a
#      "Create Multi Packet" item to the issue-list right-click context menu
#      when 2+ issues are selected. It POSTs to
#      packet_creation#create_multi_packet (after a JS confirm), streaming back
#      `multi_packet_<ts>.zip` with one `packet_<id>/ticket_<id>.pdf` per issue.
#
# Both triggers are `link_to ..., method: :post` links: @rails/ujs turns them
# into a form submission whose response is a file download, so Playwright's
# download event fires and `downloaded_zip_entries { ... }` can inspect the zip.
#
# NOTE on PDF generation: the plugin's functional test
# (test_create_packet_with_permission) skips when PDF rendering blows up in the
# bare controller-test context. The full system-test stack runs the real
# request middleware (closer to dev), where PDF generation succeeds -- these
# tests assert on the ticket PDF entries directly. See the report if that ever
# regresses.
class PacketCreationTest < AuditUtilsSystemTestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :issues,
           :issue_statuses, :trackers, :projects_trackers, :enabled_modules,
           :enumerations, :attachments, :custom_fields, :custom_values,
           :journals, :journal_details

  setup do
    # Attachment diskfiles are written/read via Attachment.storage_path, a
    # process-global the in-process Puma app thread shares with us. Point it at
    # the throwaway tmp dir so seeded attachments resolve for both sides.
    set_tmp_attachments_directory

    @project = Project.find(1)
    @project.enable_module!(:audit_utils)
    log_in_as_admin
  end

  # 1. Single-ticket packet via the attachments contextual "Create Packet"
  #    button on the issue detail page.
  def test_single_ticket_packet_download_from_issue_page
    issue = Issue.find(1)
    attachment = seed_attachment(issue, 'account_holder_form.txt')

    visit "/issues/#{issue.id}"

    # The patch only injects the button when the issue has visible attachments;
    # confirm the seeded attachment (and thus the button) is on the page.
    assert_text attachment.filename
    packet_button = find("a.icon-package[href$='/issues/#{issue.id}/create_packet']")

    entries = downloaded_zip_entries('packet_*.zip') { packet_button.click }

    assert_includes entries, "ticket_#{issue.id}.pdf",
                    "packet zip should contain the ticket PDF (entries: #{entries.inspect})"
    assert_includes entries, attachment.filename,
                    "packet zip should contain the seeded attachment (entries: #{entries.inspect})"
  end

  # 2. Bulk packet via the issue-list right-click context menu "Create Multi
  #    Packet" item (shown only when 2+ issues are selected).
  def test_bulk_packet_download_from_issue_list_context_menu
    issue1 = Issue.find(1)
    issue2 = Issue.find(2)

    visit '/issues'
    assert_selector "tr#issue-#{issue1.id}"
    assert_selector "tr#issue-#{issue2.id}"

    find("tr#issue-#{issue1.id} input[type=checkbox]").click
    find("tr#issue-#{issue2.id} input[type=checkbox]").click

    find("tr#issue-#{issue1.id} td.updated_on").right_click
    assert_selector '#context-menu'
    within '#context-menu' do
      assert_link 'Create Multi Packet'
    end

    # NOTE: the hook builds the link with a bare `confirm:` option, which modern
    # Rails renders as an inert `confirm="..."` attribute (not `data-confirm`),
    # so @rails/ujs shows NO dialog -- the click POSTs straight through and the
    # response streams the zip download. (Don't wrap this in accept_confirm; no
    # modal appears -> Capybara::ModalNotFound.)
    entries = downloaded_zip_entries('multi_packet_*.zip') do
      within('#context-menu') { click_link 'Create Multi Packet' }
    end

    assert_includes entries, "packet_#{issue1.id}/ticket_#{issue1.id}.pdf",
                    "multi-packet zip should contain issue #{issue1.id}'s PDF (entries: #{entries.inspect})"
    assert_includes entries, "packet_#{issue2.id}/ticket_#{issue2.id}.pdf",
                    "multi-packet zip should contain issue #{issue2.id}'s PDF (entries: #{entries.inspect})"
  end

  private

  # Seed a synthetic attachment on `issue` using the core test fixture file,
  # renamed so assertions target an obviously-synthetic name.
  def seed_attachment(issue, filename)
    Attachment.create!(
      container: issue,
      file: uploaded_test_file('testfile.txt', 'text/plain'),
      filename: filename,
      author: User.find(1)
    )
  end
end
