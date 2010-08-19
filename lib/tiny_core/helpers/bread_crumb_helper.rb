module TinyCore
  module BreadCrumbHelper
    def bread_crumb
      items = [%{<a href="/">#{I18n.t('breadcrumb.home')}</a>}]
      sofar = ''
      elements = request.request_uri.split('?').first.split('/')
      parent_model = nil
      for i in 1...elements.size
        sofar += '/' + elements[i]
      
        parent_model, link_text = begin
          next_model = if parent_model
            parent_model.instance_eval("#{elements[i - 1]}.from_param!('#{elements[i]}')")
          else
            eval("#{elements[i - 1].singularize.camelize}.from_param!('#{elements[i]}')")
          end
          [next_model, next_model.respond_to?(:name) ? next_model.name : next_model.to_param]
        rescue Exception => e
          [parent_model, I18n.t("breadcrumb.#{elements[i]}")]
        end
        
        if sofar == request.path
          items << "<strong>"  + link_text + '</strong>'
        else
          items << "<a href='#{sofar}'>"  + link_text + '</a>'
        end
      end
    
      content_tag :ul do
        items.collect { |item| content_tag(:li) { item } }
      end
    end
  end
end

ActionController::Base.send :helper, TinyCore::BreadCrumbHelper
