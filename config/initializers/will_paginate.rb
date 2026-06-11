require 'will_paginate/view_helpers/action_view'

module WillPaginate
  module ActionView
    class TailwindLinkRenderer < LinkRenderer
      def container_attributes
        { class: "flex justify-center items-center gap-3" }
      end

      def page_number(page)
        if page == current_page
          tag(:span, page, class: "flex items-center justify-center w-10 h-10 rounded-lg bg-blue-three text-white font-bold shadow-md transition-all")
        else
          link(page, page, rel: rel_value(page), class: "flex items-center justify-center w-10 h-10 rounded-lg bg-white border border-gray-200 text-gray-600 hover:bg-gray-50 hover:text-blue-three hover:border-blue-three font-medium transition-all")
        end
      end

      def gap
        tag(:span, "...", class: "flex items-center justify-center w-10 h-10 text-gray-400 font-medium")
      end

      def previous_or_next_page(page, text, classname, aria_label = nil)
        if page
          link(text, page, class: "flex items-center justify-center w-10 h-10 rounded-lg bg-white border border-gray-200 text-gray-600 hover:bg-gray-50 hover:text-blue-three hover:border-blue-three font-medium transition-all #{classname}", aria: { label: aria_label })
        else
          tag(:span, text, class: "flex items-center justify-center w-10 h-10 rounded-lg bg-gray-50 border border-gray-100 text-gray-300 cursor-not-allowed #{classname}", aria: { label: aria_label })
        end
      end

      def html_container(html)
        tag(:div, html, container_attributes)
      end
    end
  end
end
