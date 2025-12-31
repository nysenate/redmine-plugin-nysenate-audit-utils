Redmine::Plugin.register :nysenate_audit_utils do
  name 'NYSenate Audit Utils Plugin'
  author 'New York State Senate'
  description 'Audit utilities including packet creation (PDF + attachments) and other audit workflow tools'
  version '0.1.0'
  url 'https://github.com/nysenate/redmine-plugin-nysenate-audit-utils'
  author_url 'https://github.com/nysenate'

  requires_redmine version_or_higher: '5.0.0'
end

# Load patches and components after plugin initialization
Rails.application.config.after_initialize do
  require File.expand_path('lib/attachments_helper_patch', __dir__)
  require File.expand_path('lib/issue_context_menu_hook', __dir__)
end