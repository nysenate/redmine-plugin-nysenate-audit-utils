class IssueContextMenuHook < Redmine::Hook::ViewListener
  def view_issues_context_menu_end(context = {})
    return '' unless context[:issues]&.any?
    
    user = User.current
    issues = context[:issues]
    
    return '' unless issues.all? { |issue| user.allowed_to?(:view_issues, issue.project) }
    
    if issues.size == 1
      # Single issue selected - show single packet option
      issue = issues.first
      content_tag :li do
        link_to(
          sprite_icon('package', l(:button_create_packet)),
          { 
            controller: 'packet_creation', 
            action: 'create',
            id: issue.id
          },
          method: :post,
          class: 'icon icon-package',
          title: l(:button_create_packet_title)
        )
      end
    else
      # Multiple issues selected - show multi packet option
      content_tag :li do
        link_to(
          sprite_icon('package', l(:button_create_multi_packet)),
          { 
            controller: 'packet_creation', 
            action: 'create_multi_packet',
            ids: issues.map(&:id)
          },
          method: :post,
          class: 'icon icon-package',
          confirm: l(:text_create_multi_packet_confirm, count: issues.size)
        )
      end
    end
  end
end