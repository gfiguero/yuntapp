class Users::RegistrationsController < Devise::RegistrationsController
  layout "auth", only: [:new, :create]
end
