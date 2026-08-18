module Admin
  class MembersController < Admin::ApplicationController
    include Pagy::Method

    before_action :set_member, only: %i[show edit update approve reject deactivate confirm_deactivate]
    before_action :set_members, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/members
    def index
      @pagy, @members = pagy(@members)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/members/search.json
    def search
      scope = current_neighborhood_association.members
      @members = params[:items].present? ? scope.filter_by_id(params[:items]) : scope

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/members/1
    def show
    end

    # GET /admin/members/new
    def new
      @member = Member.new
    end

    # GET /admin/members/1/edit
    def edit
    end

    # POST /admin/members
    #
    # BR-024: el alta manual es atómica. Antes la `VerifiedIdentity` se guardaba
    # primero y el `Member` después, fuera de transacción: si el Member fallaba,
    # la identidad quedaba persistida y huérfana — una identidad verificada
    # materializada sin socio ni verificación documental (BR-044).
    #
    # El socio nace `pending` y con `requested_by` para que quede registrado qué
    # admin lo dio de alta; la aprobación sigue siendo un acto aparte (#approve),
    # que es donde se sella `approved_by`/`approved_at`.
    def create
      run = normalize_run(verified_identity_params[:run])
      verified_identity = VerifiedIdentity.find_or_initialize_by(run: run)
      verified_identity.assign_attributes(verified_identity_params.except(:run))
      verified_identity.run = run

      @member = Member.new(
        neighborhood_association: current_neighborhood_association,
        status: "pending",
        requested_by: current_user
      )

      created = false
      ActiveRecord::Base.transaction do
        unless verified_identity.save
          @member.errors.merge!(verified_identity.errors)
          raise ActiveRecord::Rollback
        end

        # Se asigna DESPUÉS de persistir: `Member` valida la presencia de
        # `verified_identity_id`, que no existe hasta que la identidad tiene id.
        @member.verified_identity = verified_identity
        raise ActiveRecord::Rollback unless @member.save
        created = true
      end

      if created
        redirect_to admin_member_path(@member), notice: I18n.t("admin.members.flash.created")
      else
        # La identidad revertida conserva los atributos tipeados: se reasigna
        # (en memoria) para que el formulario los muestre de vuelta.
        @member.verified_identity ||= verified_identity
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/members/1
    # BR-046: el RUN de una identidad ya verificada es inmutable. Corregirlo
    # exige desactivar al socio (BR-036) y rehacer el onboarding con el RUN
    # correcto, para que la junta verifique la documentación de nuevo. Permitirlo
    # aquí dejaba reescribir la identidad de un socio (y de sus certificados ya
    # emitidos) sin ninguna verificación. `create` ya lo excluía; `update` no.
    #
    # BR-024: igual que `create`, la edición es atómica y los errores de la
    # identidad se muestran en el formulario. Con `update!` un dato inválido
    # (p. ej. un teléfono mal formado) reventaba con 500 en vez de un 422.
    def update
      identity = @member.verified_identity

      updated = false
      ActiveRecord::Base.transaction do
        unless identity.update(verified_identity_params.except(:run))
          @member.errors.merge!(identity.errors)
          raise ActiveRecord::Rollback
        end

        raise ActiveRecord::Rollback unless @member.save
        updated = true
      end

      if updated
        redirect_to admin_member_path(@member), notice: I18n.t("admin.members.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # PATCH /admin/members/1/approve
    def approve
      @member.update!(
        status: "approved",
        approved_by: current_user,
        approved_at: Time.current
      )
      redirect_to admin_member_path(@member), notice: I18n.t("admin.members.flash.approved"), status: :see_other
    end

    # PATCH /admin/members/1/reject
    def reject
      @member.update!(status: "rejected", approved_by: current_user, rejection_reason: params[:rejection_reason])
      redirect_to admin_member_path(@member), notice: I18n.t("admin.members.flash.rejected"), status: :see_other
    end

    # GET /admin/members/1/deactivate
    def deactivate
    end

    # PATCH /admin/members/1/confirm_deactivate
    def confirm_deactivate
      @member.deactivate!(reason: params[:deactivation_reason])
      redirect_to admin_member_path(@member), notice: I18n.t("admin.members.flash.deactivated"), status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :deactivate, status: :unprocessable_content
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_member
      @member = current_neighborhood_association.members.find(params[:id])
    end

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def verified_identity_params
      params.require(:member).permit(:first_name, :last_name, :run, :phone, :email)
    end

    def set_members
      @members = current_neighborhood_association.members
      @members = @members.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @members = @members.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name, :run, :status).compact_blank
    end

    def disabled_pagination
      render json: current_neighborhood_association.members if params[:items] == "all"
    end
  end
end
