module Superadmin
  class RegionsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_region, only: %i[show edit update delete destroy]
    before_action :set_regions, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/regions
    def index
      @pagy, @regions = pagy(@regions)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/regions/search.json
    def search
      @regions = params[:items].present? ? Region.filter_by_id(params[:items]) : Region.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/regions/1
    def show
    end

    # GET /admin/regions/new
    def new
      @region = Region.new
    end

    # GET /admin/regions/1/edit
    def edit
    end

    # POST /admin/regions
    def create
      @region = Region.new(region_params)

      if @region.save
        redirect_to superadmin_region_path(@region), notice: I18n.t("region.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/regions/1
    def update
      if @region.update(region_params)
        redirect_to superadmin_region_path(@region), notice: I18n.t("region.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/regions/1/delete
    def delete
    end

    # DELETE /admin/regions/1
    def destroy
      @region.destroy!
      redirect_to superadmin_regions_path, notice: I18n.t("region.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_region
      @region = Region.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def region_params
      params.require(:region).permit(:name, :country_id)
    end

    def set_regions
      @regions = Region.all.includes(:country)
      @regions = @regions.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @regions = @regions.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: Region.all if params[:items] == "all"
    end
  end
end
