module ApplicationHelper
  include IconsHelper

  # Flash Messages
  def notification_class(level)
    case level
    when :notice then "notification-notice"
    when :alert then "notification-alert"
    when :error then "notification-error"
    when :success then "notification-success"
    when :created then "notification-created"
    when :updated then "notification-updated"
    when :deleted then "notification-deleted"
    end
  end

  def sort_scope(column)
    "sort_by_#{column}"
  end

  def filter_scope(attribute)
    "filter_by_#{attribute}"
  end

  def sort_link(path, text, column)
    sort_column = params[:sort_column]
    sort_direction = params[:sort_direction]
    text ||= path
    return link_to raw(text + icon("chevron-up")), send(path, request.params.merge(sort_column: column, sort_direction: "desc")), {class: "flex items-center"} if sort_column == column && sort_direction == "asc"
    return link_to raw(text + icon("chevron-down")), send(path, request.params.merge(sort_column: column, sort_direction: "asc")), {class: "flex items-center"} if sort_column == column && sort_direction == "desc"
    link_to raw(text + icon("chevron-sort")), send(path, request.params.merge(sort_column: column, sort_direction: "asc")), {class: "flex items-center"}
  end

  def notification_icon(notification_key)
    case notification_key
    when "notice" then icon("info-circle")
    when "alert" then icon("exclamation-circle")
    when "error" then icon("close-circle")
    when "success" then icon("check-circle")
    when "created" then icon("plus-circle")
    when "updated" then icon("edit")
    when "deleted" then icon("trash")
    else icon("info-circle")
    end
  end

  def error_message(invalid, messages)
    if invalid
      errors = ""
      messages.each { |message| errors += "<div class='form-control-message'>" + message + "</div>" }
      errors
    end
  end

  def status_badge(status)
    badge_class = case status
    when "approved" then "badge-success"
    when "pending" then "badge-warning"
    when "rejected" then "badge-error"
    when "draft" then "badge-ghost"
    else "badge-ghost"
    end

    label = I18n.t("panel.onboarding.status.#{status}", default: status&.capitalize)
    content_tag(:span, label, class: "badge badge-sm #{badge_class}")
  end

  def mini_token
    rand(36**8).to_s(36)
  end
end
