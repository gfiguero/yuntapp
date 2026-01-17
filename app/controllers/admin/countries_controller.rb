module Admin
  class CountriesController < ApplicationController
    include Pagy::Method

    before_action :set_country, only: %i[show edit update delete destroy]
    before_action :set_countries, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/countries
    def index
      @pagy, @countries = pagy(@countries)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/countries/search.json
    def search
      @countries = params[:items].present? ? Country.filter_by_id(params[:items]) : Country.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/countries/1
    def show
    end

    # GET /admin/countries/new
    def new
      @country = Country.new
    end

    # GET /admin/countries/1/edit
    def edit
    end

    # POST /admin/countries
    def create
      @country = Country.new(country_params)

      if @country.save
        redirect_to admin_country_path(@country), notice: I18n.t("country.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/countries/1
    def update
      if @country.update(country_params)
        redirect_to admin_country_path(@country), notice: I18n.t("country.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/countries/1/delete
    def delete
    end

    # DELETE /admin/countries/1
    def destroy
      @country.destroy!
      redirect_to admin_countries_path, notice: I18n.t("country.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_country
      @country = Country.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def country_params
      params.require(:country).permit(:name, :iso_code)
    end

    def set_countries
      @countries = Country.all
      @countries = @countries.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @countries = @countries.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: Country.all if params[:items] == "all"
    end
  end
end
