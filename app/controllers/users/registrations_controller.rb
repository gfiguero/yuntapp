class Users::RegistrationsController < Devise::RegistrationsController
  layout :resolve_layout

  private

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
