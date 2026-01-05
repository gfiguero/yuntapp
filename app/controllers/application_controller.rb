class ApplicationController < ActionController::Base
  include ApplicationHelper

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :authenticate_user!
  add_flash_types :success, :danger, :warning, :info, :error, :created, :updated, :deleted

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
