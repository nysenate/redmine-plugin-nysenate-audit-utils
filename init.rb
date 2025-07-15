Redmine::Plugin.register :bachelp_packet_creation do
  name 'BACHelp Packet Creation Plugin'
  author 'New York State Senate'
  description 'Enables creation of ticket packets (PDF + attachments) for auditing purposes'
  version '0.1.0'
  url 'https://github.com/nysenate/bachelp_packet_creation'
  author_url 'https://github.com/nysenate'

  requires_redmine version_or_higher: '5.0.0'
  
  # Define permission for packet creation
  permission :create_packet, { packet_creation: [:create] }, public: false
  
  # Add to project module for per-project configuration
  project_module :bachelp_packet_creation do
    permission :create_packet, { packet_creation: [:create] }
  end
end

# Load the view listener after plugin initialization
Rails.application.config.after_initialize do
  require File.expand_path('lib/packet_creation_view_listener', __dir__)
end