module Panel
  class OnboardingController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :redirect_if_onboarded!, except: [:restart]
    before_action :ensure_step1!, only: [:step2, :update_step2, :step3, :update_step3, :step4, :submit]
    before_action :ensure_step2!, only: [:step3, :update_step3, :step4, :submit]
    before_action :ensure_step3!, only: [:step4, :submit]
    before_action :ensure_step4!, only: [:step4, :submit]

    def restart
      # 1. Eliminar datos de sesión
      session.delete(:onboarding)

      # 2. Cancelar solicitud pendiente si existe
      current_user.current_onboarding_request&.destroy

      # 2. Eliminar asociación actual si existe (Member y HouseholdUnit)
      # Nota: Esto es destructivo. Dependiendo del negocio, quizás solo se quiera "archivar"
      # o dejar inactivo. Por ahora, eliminamos la relación actual para permitir un nuevo flujo.

      current_user.member&.destroy

      # Opcional: Si el usuario creó un HouseholdUnit específico para él y nadie más vive ahí,
      # podríamos querer eliminarlo también, pero es arriesgado si hay otros miembros.
      # Por seguridad, solo desvinculamos al usuario (eliminando su Member record).

      redirect_to panel_onboarding_step1_path, notice: "Proceso de onboarding reiniciado."
    end

    def step1
      # Si ya tiene una solicitud pendiente, la recuperamos
      @onboarding_request = current_user.current_onboarding_request

      # Si no existe, la creamos INMEDIATAMENTE
      @onboarding_request ||= OnboardingRequest.create!(
        user: current_user,
        status: "draft"
      )

      # Actualizamos sesión con el ID
      session[:onboarding] ||= {}
      session[:onboarding]["onboarding_request_id"] = @onboarding_request.id
      session[:onboarding]["neighborhood_association_id"] = @onboarding_request.neighborhood_association_id
      session[:onboarding]["identity_request_id"] = @onboarding_request.identity_verification_request&.id
      session[:onboarding]["residence_request_id"] = @onboarding_request.residence_verification_request&.id

      # Datos para el formulario
      @cascading_data = build_cascading_data

      # Selecciones guardadas para restaurar el estado del formulario
      @selected_region_id = @onboarding_request.region_id
      @selected_commune_id = @onboarding_request.commune_id
      @selected_association_id = @onboarding_request.neighborhood_association_id
    end

    def update_step1
      # Este método ahora puede recibir region_id, commune_id y neighborhood_association_id
      # para ir guardando el progreso parcial.

      @onboarding_request = current_user.current_onboarding_request
      # Fallback create if missing (should not happen due to step1 logic but safe to keep)
      @onboarding_request ||= OnboardingRequest.create!(user: current_user, status: "draft")

      # Actualizamos campos según lo que venga en params
      updates = {}

      # Si cambia la región (incluso a vacío)
      if params.key?(:region_id)
        if params[:region_id] != @onboarding_request.region_id.to_s
          updates[:region_id] = params[:region_id].presence # Guarda nil si es string vacío
          updates[:commune_id] = nil
          updates[:neighborhood_association_id] = nil
        end
      end

      # Si cambia la comuna (incluso a vacío)
      if params.key?(:commune_id)
        # Solo procesamos cambio de comuna si no se está reseteando la región al mismo tiempo (para evitar doble seteo)
        # O si ya tenemos una región válida
        if params[:commune_id] != @onboarding_request.commune_id.to_s && !updates.key?(:region_id)
          updates[:commune_id] = params[:commune_id].presence
          updates[:neighborhood_association_id] = nil
        end
      end

      # Si cambia la junta (incluso a vacío)
      if params.key?(:neighborhood_association_id)
        if params[:neighborhood_association_id] != @onboarding_request.neighborhood_association_id.to_s && !updates.key?(:commune_id)
          updates[:neighborhood_association_id] = params[:neighborhood_association_id].presence
        end
      end

      @onboarding_request.update(updates) if updates.any?

      # Si se hizo clic en el botón "Continuar" (name="commit_continue")
      # O si viene el ID y NO es una petición de Turbo Frame (fallback para navegadores sin JS/Turbo)
      if params[:commit_continue].present? && @onboarding_request.neighborhood_association_id.present?
        session[:onboarding] ||= {}
        session[:onboarding]["neighborhood_association_id"] = @onboarding_request.neighborhood_association_id
        session[:onboarding]["onboarding_request_id"] = @onboarding_request.id

        redirect_to panel_onboarding_step2_path
      else
        # Si es solo una actualización parcial (ej: cambio de región o selección de junta via onchange)
        # Respondemos con HTML para actualizar el formulario (y habilitar el botón si corresponde)

        @cascading_data = build_cascading_data
        @selected_region_id = @onboarding_request.region_id
        @selected_commune_id = @onboarding_request.commune_id
        @selected_association_id = @onboarding_request.neighborhood_association_id

        respond_to do |format|
          format.html { render :step1 }
        end
      end
    end

    # STEP 2: Identidad (Antes Step 3)
    def step2
      # Recuperamos la solicitud de onboarding
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Si ya existe una solicitud de identidad asociada, la usamos
      if @onboarding_request&.identity_verification_request
        @identity_request = @onboarding_request.identity_verification_request
      else
        # Si no, intentamos pre-llenar con datos anteriores o creamos una nueva
        last_request = current_user.identity_verification_requests.last

        # CREAMOS la solicitud inmediatamente en estado draft
        @identity_request = IdentityVerificationRequest.create!(
          user: current_user,
          neighborhood_association_id: @onboarding_request.neighborhood_association_id,
          onboarding_request: @onboarding_request,
          status: "draft",
          run: last_request&.run || current_user.verified_identity&.run,
          first_name: last_request&.first_name || current_user.verified_identity&.first_name,
          last_name: last_request&.last_name || current_user.verified_identity&.last_name,
          phone: last_request&.phone || current_user.verified_identity&.phone
        )

        # Guardamos el ID en sesión
        session[:onboarding]["identity_request_id"] = @identity_request.id
      end
    end

    def update_step2
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Recuperamos la solicitud existente (siempre debería existir por step2)
      @identity_request = @onboarding_request.identity_verification_request

      # Fallback por seguridad
      @identity_request ||= IdentityVerificationRequest.create!(
        user: current_user,
        neighborhood_association_id: @onboarding_request.neighborhood_association_id,
        onboarding_request: @onboarding_request,
        status: "draft"
      )

      # Actualizamos atributos
      @identity_request.assign_attributes(verification_params)

      # Intentamos guardar (en draft no valida campos obligatorios, pero sí formatos si los hay)
      if @identity_request.save
        @identity_request.identity_document.attach(params[:identity_verification_request][:identity_document]) if params[:identity_verification_request][:identity_document].present?

        # Guardamos el ID de la solicitud en sesión
        session[:onboarding]["identity_request_id"] = @identity_request.id

        # Si se hizo clic en continuar, VALIDAMOS COMPLETITUD y redirigimos
        if params[:commit_continue].present?
          # Validamos manualmente que estén los campos requeridos antes de avanzar
          if @identity_request.first_name.present? && @identity_request.last_name.present? && @identity_request.run.present? && @identity_request.phone.present?
            redirect_to panel_onboarding_step3_path
          else
            @identity_request.errors.add(:base, "Debes completar todos los campos obligatorios para continuar.")
            # Forzamos validación de presencia para mostrar errores en la vista
            @identity_request.valid?
            # Agregamos errores manualmente a los campos vacíos para que se iluminen
            [:first_name, :last_name, :run, :phone].each do |attr|
              @identity_request.errors.add(attr, :blank) if @identity_request.send(attr).blank?
            end

            respond_to do |format|
              format.html { render :step2, status: :unprocessable_content }
            end
          end
        else
          # Si es actualización parcial, respondemos con HTML para Turbo Frame
          respond_to do |format|
            format.html { render :step2 }
          end
        end
      else
        # Si hay errores de formato u otros
        respond_to do |format|
          format.html { render :step2, status: :unprocessable_content }
        end
      end
    end

    # STEP 3: Domicilio (Antes Step 2)
    def step3
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)

      # Pre-llenamos si existe una solicitud previa
      last_request = current_user.residence_verification_requests.last

      @residence_request = ResidenceVerificationRequest.new(
        number: last_request&.number,
        address_line_1: last_request&.address_line_1,
        address_line_2: last_request&.address_line_2,
        neighborhood_delegation_id: last_request&.neighborhood_delegation_id
      )
    end

    def update_step3
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)

      @residence_request = ResidenceVerificationRequest.new(residence_verification_params)
      @residence_request.user = current_user
      @residence_request.neighborhood_association = @neighborhood_association
      @residence_request.onboarding_request_id = session.dig(:onboarding, "onboarding_request_id")
      @residence_request.commune = @neighborhood_association.commune # Asumimos misma comuna que la junta
      @residence_request.status = "pending"

      # Rellenamos datos geográficos básicos basados en la asociación si faltan en el form
      @residence_request.region = @neighborhood_association.commune&.region&.name
      @residence_request.country = @neighborhood_association.commune&.region&.country&.name

      if @residence_request.save
        session[:onboarding]["residence_request_id"] = @residence_request.id
        redirect_to panel_onboarding_step4_path
      else
        render :step3, status: :unprocessable_content
      end
    end

    def step4
      @onboarding_request = OnboardingRequest.find(session.dig(:onboarding, "onboarding_request_id"))
      @neighborhood_association = @onboarding_request.neighborhood_association
      @identity_request = @onboarding_request.identity_verification_request
      @residence_request = @onboarding_request.residence_verification_request
    end

    def submit
      # El proceso finaliza cambiando el estado a "pending" para que sea revisado
      @onboarding_request = OnboardingRequest.find(session.dig(:onboarding, "onboarding_request_id"))
      @onboarding_request.update!(status: "pending")

      # También pasamos las solicitudes hijas a pending
      @onboarding_request.identity_verification_request&.update!(status: "pending")
      @onboarding_request.residence_verification_request&.update!(status: "pending")

      session.delete(:onboarding)
      redirect_to panel_root_path, notice: "Solicitud de incorporación enviada exitosamente. Te notificaremos cuando sea aprobada."
    end

    private

    def redirect_if_onboarded!
      redirect_to panel_root_path if current_user.member.present?
    end

    def ensure_step1!
      # Solo verificamos que no tenga un onboarding request pendiente
      # Pero el step 1 es donde comienza, así que no hay prerrequisitos de sesión, solo que no tenga ya un proceso terminado.
    end

    def ensure_step2!
      # Debe existir una solicitud de onboarding en sesión (creada en step 1)
      redirect_to panel_onboarding_step1_path unless session.dig(:onboarding, "onboarding_request_id").present?
    end

    def ensure_step3!
      # Debe haber completado step 2 (Identidad) -> identity_request_id en sesión
      redirect_to panel_onboarding_step2_path unless session.dig(:onboarding, "identity_request_id").present?
    end

    def ensure_step4!
      # Debe haber completado step 3 (Residencia) -> residence_request_id en sesión
      redirect_to panel_onboarding_step3_path unless session.dig(:onboarding, "residence_request_id").present?
    end

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def verification_params
      params.require(:identity_verification_request).permit(:first_name, :last_name, :run, :phone)
    end

    def residence_verification_params
      params.require(:residence_verification_request).permit(:number, :address_line_1, :address_line_2, :neighborhood_delegation_id)
    end

    def build_cascading_data
      associations_by_commune = NeighborhoodAssociation.where.not(commune_id: nil).order(:name).group_by(&:commune_id)
      commune_ids = associations_by_commune.keys
      communes = Commune.where(id: commune_ids).order(:name).includes(:region)

      communes.group_by { |c| c.region }.map do |region, region_communes|
        {
          id: region.id,
          name: region.name,
          communes: region_communes.sort_by(&:name).map do |commune|
            {
              id: commune.id,
              name: commune.name,
              associations: (associations_by_commune[commune.id] || []).map do |assoc|
                {id: assoc.id, name: assoc.name}
              end
            }
          end
        }
      end.sort_by { |r| r[:name] }
    end
  end
end
