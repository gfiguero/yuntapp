module Superadmin
  class CommunesController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_commune, only: %i[show edit update delete destroy]
    before_action :set_communes, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/communes
    def index
      @pagy, @communes = pagy(@communes)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/communes/search.json
    def search
      @communes = params[:items].present? ? Commune.filter_by_id(params[:items]) : Commune.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/communes/1
    def show
    end

    # GET /admin/communes/new
    def new
      @commune = Commune.new
    end

    # GET /admin/communes/1/edit
    def edit
    end

    # POST /admin/communes
    def create
      @commune = Commune.new(commune_params)

      if @commune.save
        redirect_to superadmin_commune_path(@commune), notice: I18n.t("commune.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/communes/1
    def update
      if @commune.update(commune_params)
        redirect_to superadmin_commune_path(@commune), notice: I18n.t("commune.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/communes/1/delete
    def delete
    end

    # DELETE /admin/communes/1
    def destroy
      @commune.destroy!
      redirect_to superadmin_communes_path, notice: I18n.t("commune.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_commune
      @commune = Commune.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def commune_params
      params.require(:commune).permit(:name, :region_id)
    end

    def set_communes
      @communes = Commune.all
      @communes = @communes.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @communes = @communes.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: Commune.all if params[:items] == "all"
    end
  end
end
