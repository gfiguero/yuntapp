module Admin
  class MembersController < Admin::ApplicationController
    include Pagy::Method

    before_action :set_member, only: %i[show edit update delete destroy approve reject]
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
      @members = params[:items].present? ? Member.filter_by_id(params[:items]) : Member.all

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
    def create
      run = normalize_run(persona_params[:run])
      persona = Persona.find_or_initialize_by(run: run)
      persona.assign_attributes(persona_params.except(:run))
      persona.run = run
      persona.verification_status ||= "pending"

      unless persona.save
        @member = Member.new
        @member.errors.merge!(persona.errors)
        render :new, status: :unprocessable_content
        return
      end

      @member = Member.new(household_unit_id: params.dig(:member, :household_unit_id))
      @member.persona = persona

      if @member.save
        redirect_to admin_member_path(@member), notice: I18n.t("member.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/members/1
    def update
      @member.persona.update!(persona_params)
      if @member.update(household_unit_id: params.dig(:member, :household_unit_id))
        redirect_to admin_member_path(@member), notice: I18n.t("member.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/members/1/delete
    def delete
    end

    # DELETE /admin/members/1
    def destroy
      @member.destroy!
      redirect_to admin_members_path, notice: I18n.t("member.message.destroyed"), status: :see_other, format: :html
    end

    # PATCH /admin/members/1/approve
    def approve
      @member.update!(
        status: "approved",
        approved_by: current_user,
        approved_at: Time.current,
        household_admin: @member.user.present? && @member.household_unit.household_admin.nil?
      )
      redirect_to admin_member_path(@member), notice: I18n.t("member.message.approved"), status: :see_other
    end

    # PATCH /admin/members/1/reject
    def reject
      @member.update!(status: "rejected", approved_by: current_user, rejection_reason: params[:rejection_reason])
      redirect_to admin_member_path(@member), notice: I18n.t("member.message.rejected"), status: :see_other
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

    def persona_params
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
      params.permit(:id, :name, :run, :status).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: current_neighborhood_association.members if params[:items] == "all"
    end
  end
end
