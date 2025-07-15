class PacketCreationViewListener < Redmine::Hook::ViewListener
  def view_issues_show_description_bottom(context = {})
    issue = context[:issue]
    return '' unless issue
    
    # Check if the module is enabled for the project
    return '' unless issue.project.module_enabled?(:bachelp_packet_creation)
    
    # Check if user has permission to create packets
    return '' unless User.current.allowed_to?(:create_packet, issue.project)
    
    # Create the packet creation button
    link_to(
      content_tag(:span, '', class: 'icon icon-package') + l(:button_create_packet),
      create_packet_issue_path(issue),
      method: :post,
      class: 'icon icon-package',
      title: l(:button_create_packet_title)
    )
  end
end