module IconsHelper
  def icon(icon_name, icon_class = "w-6 h-6", view_box = nil)
    case icon_name
    when "info-circle"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z"/>
          </svg>
        ICON
      )
    when "exclamation-circle"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM10 15a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm1-4a1 1 0 0 1-2 0V6a1 1 0 0 1 2 0v5Z"/>
          </svg>
        ICON
      )
    when "close-circle"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5Zm3.707 11.793a1 1 0 1 1-1.414 1.414L10 11.414l-2.293 2.293a1 1 0 0 1-1.414-1.414L8.586 10 6.293 7.707a1 1 0 0 1 1.414-1.414L10 8.586l2.293-2.293a1 1 0 0 1 1.414 1.414L11.414 10l2.293 2.293Z"/>
          </svg>
        ICON
      )
    when "check-circle"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5Zm3.707 8.207-4 4a1 1 0 0 1-1.414 0l-2-2a1 1 0 0 1 1.414-1.414L9 10.586l3.293-3.293a1 1 0 0 1 1.414 1.414Z"/>
          </svg>
        ICON
      )
    when "plus-circle"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M9.546.5a9.5 9.5 0 1 0 9.5 9.5 9.51 9.51 0 0 0-9.5-9.5ZM13.788 11h-3.242v3.242a1 1 0 1 1-2 0V11H5.304a1 1 0 0 1 0-2h3.242V5.758a1 1 0 0 1 2 0V9h3.242a1 1 0 1 1 0 2Z"/>
          </svg>
        ICON
      )
    when "edit"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 18"}">
            <path d="M12.687 14.408a3.01 3.01 0 0 1-1.533.821l-3.566.713a3 3 0 0 1-3.53-3.53l.713-3.566a3.01 3.01 0 0 1 .821-1.533L10.905 2H2.167A2.169 2.169 0 0 0 0 4.167v11.666A2.169 2.169 0 0 0 2.167 18h11.666A2.169 2.169 0 0 0 16 15.833V11.1l-3.313 3.308Zm5.53-9.065.546-.546a2.518 2.518 0 0 0 0-3.56 2.576 2.576 0 0 0-3.559 0l-.547.547 3.56 3.56Z"/>
            <path d="M13.243 3.2 7.359 9.081a.5.5 0 0 0-.136.256L6.51 12.9a.5.5 0 0 0 .59.59l3.566-.713a.5.5 0 0 0 .255-.136L16.8 6.757 13.243 3.2Z"/>
          </svg>
        ICON
      )
    when "trash", "delete"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 18 20"}">
            <path d="M17 4h-4V2a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v2H1a1 1 0 0 0 0 2h1v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V6h1a1 1 0 1 0 0-2ZM7 2h4v2H7V2Zm1 14a1 1 0 1 1-2 0V8a1 1 0 0 1 2 0v8Zm4 0a1 1 0 0 1-2 0V8a1 1 0 0 1 2 0v8Z"/>
          </svg>
        ICON
      )
    when "grid-plus", "new"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 18 18"}">
            <path d="M6.143 0H1.857A1.857 1.857 0 0 0 0 1.857v4.286C0 7.169.831 8 1.857 8h4.286A1.857 1.857 0 0 0 8 6.143V1.857A1.857 1.857 0 0 0 6.143 0Zm10 0h-4.286A1.857 1.857 0 0 0 10 1.857v4.286C10 7.169 10.831 8 11.857 8h4.286A1.857 1.857 0 0 0 18 6.143V1.857A1.857 1.857 0 0 0 16.143 0Zm-10 10H1.857A1.857 1.857 0 0 0 0 11.857v4.286C0 17.169.831 18 1.857 18h4.286A1.857 1.857 0 0 0 8 16.143v-4.286A1.857 1.857 0 0 0 6.143 10ZM17 13h-2v-2a1 1 0 0 0-2 0v2h-2a1 1 0 0 0 0 2h2v2a1 1 0 0 0 2 0v-2h2a1 1 0 0 0 0-2Z"/>
          </svg>
        ICON
      )
    when "show"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="m19.707 18.293-4-4a1 1 0 0 0-1.414 1.414l4 4a1 1 0 0 0 1.414-1.414ZM8 .5A7.5 7.5 0 1 0 15.5 8 7.508 7.508 0 0 0 8 .5ZM11 9H9v2a1 1 0 1 1-2 0V9H5a1 1 0 0 1 0-2h2V5a1 1 0 0 1 2 0v2h2a1 1 0 1 1 0 2Z"/>
          </svg>
        ICON
      )
    when "filter"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 18"}">
            <path d="M18.85 1.1A1.99 1.99 0 0 0 17.063 0H2.937a2 2 0 0 0-1.566 3.242L6.99 9.868 7 14a1 1 0 0 0 .4.8l4 3A1 1 0 0 0 13 17l.01-7.134 5.66-6.676a1.99 1.99 0 0 0 .18-2.09Z"/>
          </svg>
        ICON
      )
    when "close"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 14 14"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m1 1 6 6m0 0 6 6M7 7l6-6M7 7l-6 6"/>
          </svg>
        ICON
      )
    when "chevron-left", "back"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 6 10"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 1 1 5l4 4"/>
          </svg>
        ICON
      )
    when "chevron-right", "forward"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 10 10"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m1 9 4-4-4-4"/>
          </svg>
        ICON
      )
    when "chevron-up"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 10 10"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5 5 1 1 5"/>
          </svg>
        ICON
      )
    when "chevron-down"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 10 10"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m1 1 4 4 4-4"/>
          </svg>
        ICON
      )
    when "chevron-sort"
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="#{view_box || "0 0 10 16"}">
            <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5 5 1 1 5m0 6 4 4 4-4"/>
          </svg>
        ICON
      )
    else
      raw(
        <<-ICON
          <svg class="#{icon_class}" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="#{view_box || "0 0 20 20"}">
            <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z"/>
          </svg>
        ICON
      )
    end
  end
end
