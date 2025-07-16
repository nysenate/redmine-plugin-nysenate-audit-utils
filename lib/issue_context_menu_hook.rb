class IssueContextMenuHook < Redmine::Hook::ViewListener
  def view_issues_context_menu_end(context = {})
    return '' unless context[:issues]&.size&.> 1
    
    user = User.current
    issues = context[:issues]
    
    return '' unless issues.all? { |issue| user.allowed_to?(:view_issues, issue.project) }
    
    link_to(
      l(:button_create_multi_packet),
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