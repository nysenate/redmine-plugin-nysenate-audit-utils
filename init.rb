Redmine::Plugin.register :bachelp_packet_creation do
  name 'BACHelp Packet Creation Plugin'
  author 'New York State Senate'
  description 'Enables creation of ticket packets (PDF + attachments) for auditing purposes'
  version '0.1.0'
  url 'https://github.com/nysenate/bachelp_packet_creation'
  author_url 'https://github.com/nysenate'

  requires_redmine version_or_higher: '5.0.0'
end

# Load patches and components after plugin initialization
Rails.application.config.after_initialize do
  require File.expand_path('lib/attachments_helper_patch', __dir__)
  require File.expand_path('lib/issue_context_menu_hook', __dir__)
  require File.expand_path('lib/multi_packet_creation_service', __dir__)
end