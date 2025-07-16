module AttachmentsHelperPatch
  def self.included(base)
    base.send(:include, InstanceMethods)
    base.class_eval do
      alias_method :link_to_attachments_without_packet_creation, :link_to_attachments
      alias_method :link_to_attachments, :link_to_attachments_with_packet_creation
    end
  end

  module InstanceMethods
    def link_to_attachments_with_packet_creation(container, options = {})
      # Call the original method to get the default attachments HTML
      original_html = link_to_attachments_without_packet_creation(container, options)
      
      # Only add our button for Issues with attachments that the user can view
      if container.is_a?(Issue) && container.attachments.any? && 
         container.attachments_visible?(User.current)
        
        # Parse the original HTML to add our button to the contextual menu
        doc = Nokogiri::HTML::DocumentFragment.parse(original_html)
        contextual_div = doc.at_css('.contextual')
        
        if contextual_div
          # Create the packet creation button
          packet_button = link_to(sprite_icon('package', l(:button_create_packet)),
                                  create_packet_issue_path(container),
                                  method: :post,
                                  class: 'icon-only icon-package',
                                  title: l(:button_create_packet_title))
          
          # Add the button to the contextual menu
          contextual_div.add_child(packet_button)
        end
        
        doc.to_html.html_safe
      else
        original_html
      end
    end
  end
end

# Apply the patch
AttachmentsHelper.send(:include, AttachmentsHelperPatch)