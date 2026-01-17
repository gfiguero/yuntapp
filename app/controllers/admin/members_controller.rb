module Admin
  class MembersController < ApplicationController
    include Pagy::Method

    before_action :set_member, only: %i[show edit update delete destroy]
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
      @member = Member.new(member_params)

      if @member.save
        redirect_to admin_member_path(@member), notice: I18n.t("member.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/members/1
    def update
      if @member.update(member_params)
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

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_member
      @member = Member.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def member_params
      params.require(:member).permit(:first_name, :last_name, :run, :phone, :email, :household_unit_id)
    end

    def set_members
      @members = Member.all
      @members = @members.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @members = @members.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :first_name, :last_name, :run).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: Member.all if params[:items] == "all"
    end
  end
end
