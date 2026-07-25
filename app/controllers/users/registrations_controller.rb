class Users::RegistrationsController < Devise::RegistrationsController
  layout :resolve_layout

  before_action :discard_email_param, only: :update

  private

  # BR-093: el email de la cuenta es inmutable después del registro. La vista
  # lo muestra deshabilitado; aquí se descarta el parámetro por si llega igual
  # (formulario manipulado o request directo).
  def discard_email_param
    params[:user].delete(:email) if params[:user].is_a?(ActionController::Parameters)
  end

  # El registro (new/create) es público y usa el layout de autenticación;
  # la gestión de la cuenta (edit/update) ocurre con sesión iniciada y debe
  # verse como una página más del panel.
  def resolve_layout
    case action_name
    when "new", "create" then "auth"
    else "panel"
    end
  end
end
