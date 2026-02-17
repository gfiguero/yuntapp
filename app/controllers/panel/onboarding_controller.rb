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
      @selected_region_id = params[:region_id]
      @selected_commune_id = params[:commune_id]
      @selected_association_id = params[:neighborhood_association_id]

      # Si cambió la región, reseteamos comuna y asociación
      # Detectamos cambio si viene región pero no comuna (indicando que el submit fue del selector de región)
      # O comparamos con lo que había en sesión si quisiéramos ser más estrictos, pero el frontend envía lo que tiene.
      # La lógica de cascada simple es: Si llega region_id nuevo, y commune_id no coincide con una válida de esa región (o está vacío), resetear.

      # Lógica de cascada:
      # El formulario de región solo envía :region_id.
      # El formulario de comuna envía :commune_id y :region_id (hidden).

      # Si commit_continue está presente, intentamos avanzar
      if params[:commit_continue].present?
        if @selected_association_id.present?
          # Aseguramos persistencia antes de continuar
          @onboarding_request = current_user.current_onboarding_request
          @onboarding_request ||= OnboardingRequest.create!(user: current_user, status: "draft")
          @onboarding_request.update(
            region_id: @selected_region_id,
            commune_id: @selected_commune_id,
            neighborhood_association_id: @selected_association_id
          )

          session[:onboarding]["neighborhood_association_id"] = @selected_association_id
          session[:onboarding]["onboarding_request_id"] = @onboarding_request.id

          redirect_to panel_onboarding_step2_path
        else
          # Esto no debería pasar si el botón está disabled, pero por seguridad:
          respond_to do |format|
            format.html { render :step1, status: :unprocessable_content }
          end
        end
        return
      end

      # Si no es continuar, es una actualización de selectores

      # Si se seleccionó región (y no venía comuna, o venía pero queremos validar cascada)
      # Al cambiar región, el params[:commune_id] no vendrá porque el form de región no lo incluye.
      # Por lo tanto, si params[:commune_id] es nil, asumimos reset de comuna.
      if params[:region_id].present? && params[:commune_id].nil?
        @selected_commune_id = nil
        @selected_association_id = nil
      end

      # Si se seleccionó comuna (y no venía asociación)
      if params[:commune_id].present? && params[:neighborhood_association_id].nil?
        @selected_association_id = nil
      end

      # Persistencia parcial (opcional pero recomendada para no perder progreso si refrescan)
      @onboarding_request = current_user.current_onboarding_request
      @onboarding_request&.update(
        region_id: @selected_region_id,
        commune_id: @selected_commune_id,
        neighborhood_association_id: @selected_association_id
      )

      @cascading_data = build_cascading_data

      respond_to do |format|
        format.turbo_stream do
          streams = []

          # Siempre actualizamos el selector de región (para feedback visual de selección)
          streams << turbo_stream.replace("field_region", partial: "panel/onboarding/step1_field_region", locals: {cascading_data: @cascading_data, selected_region_id: @selected_region_id})

          # Actualizamos selector de comuna (contenido cambia según región)
          streams << turbo_stream.replace("field_commune", partial: "panel/onboarding/step1_field_commune", locals: {cascading_data: @cascading_data, selected_region_id: @selected_region_id, selected_commune_id: @selected_commune_id})

          # Actualizamos selector de asociación (contenido cambia según comuna)
          streams << turbo_stream.replace("field_association", partial: "panel/onboarding/step1_field_association", locals: {cascading_data: @cascading_data, selected_region_id: @selected_region_id, selected_commune_id: @selected_commune_id, selected_association_id: @selected_association_id})

          # Actualizamos botón submit (habilitar/deshabilitar)
          streams << turbo_stream.replace("step1_submit_button", partial: "panel/onboarding/step1_submit_button", locals: {selected_association_id: @selected_association_id, selected_region_id: @selected_region_id, selected_commune_id: @selected_commune_id})

          render turbo_stream: streams
        end
        format.html { render :step1 }
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
        current_user.identity_verification_requests.last

        # CREAMOS la solicitud inmediatamente en estado draft
        # NO pre-llenamos datos (limpieza de proceso de revalidación)

        @identity_request = IdentityVerificationRequest.new(
          user: current_user,
          onboarding_request: @onboarding_request,
          status: "draft"
        )

        if @identity_request.save
          # Guardamos el ID en sesión
          session[:onboarding]["identity_request_id"] = @identity_request.id
        else
          # Si falla al crear (ej: validaciones de unicidad u otros), manejamos el error
          # Probablemente redirigir a step1 o mostrar un error
          flash[:alert] = "No se pudo iniciar el paso de identidad: #{@identity_request.errors.full_messages.join(", ")}"
          redirect_to panel_onboarding_step1_path
        end
      end
    end

    def update_step2
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Recuperamos la solicitud existente
      @identity_request = @onboarding_request.identity_verification_request

      # Si no existe, la inicializamos (sin guardar bang!)
      if @identity_request.nil?
        @identity_request = IdentityVerificationRequest.new(
          user: current_user,
          onboarding_request: @onboarding_request,
          status: "draft"
        )
      end

      # Actualizamos atributos
      @identity_request.assign_attributes(verification_params)

      # Intentamos guardar (en draft no valida campos obligatorios, pero sí formatos si los hay)
      # Forzamos validación para ver si hay errores de formato, pero permitimos guardar si es draft
      if @identity_request.save
        # La adjunción de documentos ya se manejó automáticamente mediante assign_attributes(verification_params)
        # al inicio del método, ya que verification_params incluye :identity_documents.
        # No es necesario llamar a attach manualmente.

        # Guardamos el ID de la solicitud en sesión
        session[:onboarding]["identity_request_id"] = @identity_request.id

        # Si se hizo clic en continuar, VALIDAMOS COMPLETITUD y redirigimos
        if params[:commit_continue].present?
          # Validamos manualmente que estén los campos requeridos antes de avanzar
          if @identity_request.first_name.present? && @identity_request.last_name.present? && @identity_request.run.present? && @identity_request.phone.present? && @identity_request.identity_documents.attached?
            redirect_to panel_onboarding_step3_path
          else
            @identity_request.errors.add(:base, "Debes completar todos los campos obligatorios para continuar.")
            # Forzamos validación de presencia para mostrar errores en la vista
            # Agregamos errores manualmente a los campos vacíos para que se iluminen
            [:first_name, :last_name, :run, :phone].each do |attr|
              @identity_request.errors.add(attr, :blank) if @identity_request.send(attr).blank?
            end
            @identity_request.errors.add(:identity_documents, :blank) unless @identity_request.identity_documents.attached?

            respond_to do |format|
              format.html { render :step2, status: :unprocessable_content }
            end
          end
        else
          # Si es actualización parcial (autosave), validamos SOLO los campos que se enviaron

          # Identificamos qué campo se envió
          field_name = params[:identity_verification_request].keys.first

          # Limpiamos errores de OTROS campos
          @identity_request.errors.attribute_names.each do |attr|
            next if attr == :base
            unless attr.to_s == field_name.to_s
              @identity_request.errors.delete(attr)
            end
          end

          # Validamos presencia solo para el campo enviado
          if @identity_request.send(field_name).blank?
            @identity_request.errors.add(field_name, :blank)
          end

          # Estrategia Correcta: Devolver Turbo Streams para actualizar:
          # 1. El campo que se editó (con su validación visual)
          # 2. El botón de continuar (habilitar/deshabilitar)

          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: [
                # Reemplazamos el frame del campo específico extrayéndolo de la vista completa (truco de rendering)
                # O mejor, usamos un partial genérico si es posible, pero como cada campo es diferente,
                # lo más limpio ahora es renderizar inline el contenido del frame específico.

                # Opción pragmática: Actualizamos el frame del campo usando `replace` con el contenido renderizado del bloque correspondiente
                # Pero eso requiere tener el bloque aislado.

                # Vamos a usar una técnica de "Self-Replacement" usando `render_to_string` y Nokogiri? No, muy lento.
                # Mejor refactorizar la vista para usar partials por campo.

                turbo_stream.replace("field_#{field_name}", partial: "panel/onboarding/step2_field_#{field_name}", locals: {identity_request: @identity_request}),

                # Actualizamos el botón
                turbo_stream.replace("step2_submit_button", partial: "panel/onboarding/step2_submit_button", locals: {identity_request: @identity_request})
              ]
            end
            # Fallback para navegadores sin JS
            format.html { render :step2 }
          end
        end
      else
        # Si falla el guardado (ej: formato inválido), mostramos errores
        # Pero limpiamos errores irrelevantes
        if params[:identity_verification_request].present?
          field_name = params[:identity_verification_request].keys.first
          @identity_request.errors.attribute_names.each do |attr|
            next if attr == :base
            unless attr.to_s == field_name.to_s
              @identity_request.errors.delete(attr)
            end
          end
        end

        respond_to do |format|
          format.html { render :step2, status: :unprocessable_content }
        end
      end
    end

    def delete_document
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))
      @identity_request = @onboarding_request.identity_verification_request

      if @identity_request
        attachment = @identity_request.identity_documents.find_by(id: params[:attachment_id])
        attachment&.purge
      end

      respond_to do |format|
        format.html { redirect_to panel_onboarding_step2_path }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("field_identity_documents", partial: "panel/onboarding/step2_field_identity_documents", locals: {identity_request: @identity_request}),
            turbo_stream.replace("step2_submit_button", partial: "panel/onboarding/step2_submit_button", locals: {identity_request: @identity_request})
          ]
        end
      end
    end

    # STEP 3: Confirmación (Antes Step 4)
    def step3
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)

      # Recuperamos la solicitud de onboarding
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Si ya existe una solicitud de residencia asociada, la usamos
      if @onboarding_request&.residence_verification_request
        @residence_request = @onboarding_request.residence_verification_request
      else
        # Si no, creamos una nueva vacía
        @residence_request = ResidenceVerificationRequest.new(
          user: current_user,
          neighborhood_association_id: @onboarding_request.neighborhood_association_id,
          commune_id: @onboarding_request.commune_id,
          onboarding_request: @onboarding_request,
          status: "draft"
        )

        # Guardamos inmediatamente en draft para tener ID y persistencia
        if @residence_request.save
          session[:onboarding]["residence_request_id"] = @residence_request.id
        else
          flash[:alert] = "No se pudo iniciar el paso de residencia: #{@residence_request.errors.full_messages.join(", ")}"
          redirect_to panel_onboarding_step2_path
        end
      end
    end

    def update_step3
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)

      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Recuperamos la solicitud existente asociada al onboarding request
      @residence_request = @onboarding_request.residence_verification_request

      # Fallback por si no existiera (aunque debería por step3)
      if @residence_request.nil?
        @residence_request = ResidenceVerificationRequest.new(
          user: current_user,
          neighborhood_association_id: @onboarding_request.neighborhood_association_id,
          commune_id: @onboarding_request.commune_id,
          onboarding_request: @onboarding_request,
          status: "draft"
        )
      end

      # Actualizamos atributos
      @residence_request.assign_attributes(residence_verification_params)

      # Intentamos guardar
      if @residence_request.save
        session[:onboarding]["residence_request_id"] = @residence_request.id

        # Si se hizo clic en continuar
        if params[:commit_continue].present?
          # Validamos completitud
          has_location = @residence_request.neighborhood_delegation_id.present? || @residence_request.address_line_1.present?
          if @residence_request.number.present? && has_location
            redirect_to panel_onboarding_step4_path
          else
            @residence_request.errors.add(:base, "Debes completar los campos obligatorios.")
            # Forzamos errores visuales
            @residence_request.errors.add(:number, :blank) if @residence_request.number.blank?
            unless has_location
              @residence_request.errors.add(:neighborhood_delegation_id, :blank) if @residence_request.address_line_1.blank?
              @residence_request.errors.add(:address_line_1, :blank) if @residence_request.neighborhood_delegation_id.blank?
            end

            respond_to do |format|
              format.html { render :step3, status: :unprocessable_content }
            end
          end
        else
          # Actualización parcial (Autosave)
          # Identificamos qué campo se envió para actualizar solo ese frame

          respond_to do |format|
            format.turbo_stream do
              streams = []

              # Si se envió delegación, dirección manual o checkbox manual
              if params[:residence_verification_request].key?(:neighborhood_delegation_id) ||
                  params[:residence_verification_request].key?(:address_line_1) ||
                  params[:residence_verification_request].key?(:manual_address)

                streams << turbo_stream.replace("field_delegation_address", partial: "panel/onboarding/step3_field_delegation_address", locals: {residence_request: @residence_request, delegations: @delegations})
              end

              # Si se envió número
              if params[:residence_verification_request].key?(:number)
                streams << turbo_stream.replace("field_number", partial: "panel/onboarding/step3_field_number", locals: {residence_request: @residence_request})
              end

              # Si se envió detalle
              if params[:residence_verification_request].key?(:address_line_2)
                streams << turbo_stream.replace("field_address_line_2", partial: "panel/onboarding/step3_field_address_line_2", locals: {residence_request: @residence_request})
              end

              # Siempre actualizamos el botón de continuar
              streams << turbo_stream.replace("step3_submit_button", partial: "panel/onboarding/step3_submit_button", locals: {residence_request: @residence_request})

              render turbo_stream: streams
            end
            format.html { render :step3 }
          end
        end
      else
        # Si falla validación
        respond_to do |format|
          format.html { render :step3, status: :unprocessable_content }
          format.turbo_stream do
            # Renderizamos los mismos streams para mostrar errores
            streams = []
            streams << turbo_stream.replace("field_delegation_address", partial: "panel/onboarding/step3_field_delegation_address", locals: {residence_request: @residence_request, delegations: @delegations})
            streams << turbo_stream.replace("field_number", partial: "panel/onboarding/step3_field_number", locals: {residence_request: @residence_request})
            streams << turbo_stream.replace("field_address_line_2", partial: "panel/onboarding/step3_field_address_line_2", locals: {residence_request: @residence_request})
            streams << turbo_stream.replace("step3_submit_button", partial: "panel/onboarding/step3_submit_button", locals: {residence_request: @residence_request})
            render turbo_stream: streams
          end
        end
      end
    end

    def step4
      @onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      # Si no encontramos la solicitud principal, algo anda mal con la sesión
      if @onboarding_request.nil?
        redirect_to panel_onboarding_step1_path
        return
      end

      # Cargamos las asociaciones a través del onboarding_request para garantizar consistencia
      @neighborhood_association = @onboarding_request.neighborhood_association
      @identity_request = @onboarding_request.identity_verification_request
      @residence_request = @onboarding_request.residence_verification_request

      # Validación final: Si falta alguna pieza clave, redirigimos al paso correspondiente
      unless @neighborhood_association && @identity_request && @residence_request
        flash[:alert] = "Faltan datos para completar el resumen. Por favor revisa los pasos anteriores."
        redirect_to panel_onboarding_step1_path
      end
    end

    def submit
      @onboarding_request = OnboardingRequest.find(session.dig(:onboarding, "onboarding_request_id"))

      unless params[:terms_accepted] == "1"
        redirect_to panel_onboarding_step4_path, alert: I18n.t("panel.onboarding.step4.terms_required")
        return
      end

      # El proceso finaliza cambiando el estado a "pending" para que sea revisado
      @onboarding_request.update!(status: "pending", terms_accepted_at: Time.current)

      # También pasamos las solicitudes hijas a pending
      @onboarding_request.identity_verification_request&.update!(status: "pending")
      @onboarding_request.residence_verification_request&.update!(status: "pending")

      session.delete(:onboarding)
      redirect_to panel_root_path, notice: I18n.t("panel.onboarding.flash.completed")
    end

    private

    def redirect_if_onboarded!
      redirect_to panel_root_path if current_user.member.present?
    end

    def ensure_step1!
      onboarding_request_id = session.dig(:onboarding, "onboarding_request_id")

      unless onboarding_request_id.present?
        redirect_to panel_onboarding_step1_path, alert: "Debes completar el paso 1 primero."
        return
      end

      onboarding_request = OnboardingRequest.find_by(id: onboarding_request_id)

      unless onboarding_request&.neighborhood_association_id.present?
        redirect_to panel_onboarding_step1_path, alert: "Debes seleccionar una asociación vecinal para continuar."
      end
    end

    def ensure_step2!
      onboarding_request = OnboardingRequest.find_by(id: session.dig(:onboarding, "onboarding_request_id"))

      unless onboarding_request&.identity_verification_request.present?
        redirect_to panel_onboarding_step2_path, alert: "Debes completar el paso de identidad primero."
      end
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
      # Permitimos parámetros vacíos si vienen del botón continuar (dummy)
      if params[:identity_verification_request].present?
        params.fetch(:identity_verification_request, {}).permit(:first_name, :last_name, :run, :phone, :email, identity_documents: [])
      else
        {}
      end
    end

    def residence_verification_params
      # Permitimos parámetros vacíos si vienen del botón continuar (dummy)
      # Pero si vienen datos reales, los procesamos.
      if params[:residence_verification_request].present?
        params.require(:residence_verification_request).permit(:number, :address_line_1, :address_line_2, :neighborhood_delegation_id, :manual_address)
      else
        {}
      end
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
