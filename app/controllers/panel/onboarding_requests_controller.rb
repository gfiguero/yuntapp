module Panel
  # Historial de solicitudes de onboarding del usuario (BR-047) y duplicación de
  # las resueltas (BR-048/BR-049).
  #
  # El wizard (`Panel::OnboardingController`) trabaja siempre sobre
  # `current_onboarding_request`, que abarca solo `draft` y `pending`. Una
  # solicitud rechazada o cancelada sale de ese alcance y quedaba invisible para
  # el usuario, junto con su motivo de rechazo. Este controller es esa ventana.
  class OnboardingRequestsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    # GET /panel/onboarding/history
    def index
      @onboarding_requests = current_user.onboarding_requests
        .includes(:neighborhood_association, :identity_verification_request)
        .order(created_at: :desc)
    end

    # POST /panel/onboarding/history/:id/duplicate
    def duplicate
      # Scopeado por `current_user`: el id viaja por la URL y un POST manipulado
      # no debe alcanzar la solicitud de otro vecino.
      source = current_user.onboarding_requests.find(params[:id])

      unless source.duplicable?
        redirect_to panel_onboarding_history_path,
          alert: I18n.t("panel.onboarding_requests.flash.not_duplicable")
        return
      end

      # El wizard asume una sola solicitud activa; abrir una segunda dejaría dos
      # candidatas para `current_onboarding_request`.
      if current_user.current_onboarding_request.present?
        redirect_to panel_onboarding_history_path,
          alert: I18n.t("panel.onboarding_requests.flash.already_active")
        return
      end

      source.duplicate!

      # `step1` reconstruye la sesión del wizard desde `current_onboarding_request`,
      # que ahora es la copia recién creada.
      session.delete(:onboarding)
      redirect_to panel_onboarding_step1_path,
        notice: I18n.t("panel.onboarding_requests.flash.duplicated")
    end
  end
end
