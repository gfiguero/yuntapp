module Panel
  class ListingsController < ApplicationController
    include Pagy::Method

    before_action :authenticate_user!
    before_action :set_listing, only: %i[show edit update delete destroy]
    before_action :set_listings, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }
    layout "panel"

    # GET /panel/listings
    def index
      @pagy, @listings = pagy(@listings)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /panel/listings/search.json
    def search
      @listings = params[:items].present? ? current_user.listings.filter_by_id(params[:items]) : current_user.listings.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /panel/listings/1
    def show
    end

    # GET /panel/listings/new
    def new
      @listing = current_user.listings.new
    end

    # GET /panel/listings/1/edit
    def edit
    end

    # POST /panel/listings
    def create
      @listing = current_user.listings.new(listing_params)

      if @listing.save
        redirect_to panel_listing_path(@listing), notice: I18n.t("panel.listings.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /panel/listings/1
    def update
      if @listing.update(listing_params)
        redirect_to panel_listing_path(@listing), notice: I18n.t("panel.listings.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /panel/listings/1/delete
    def delete
    end

    # DELETE /panel/listings/1
    def destroy
      @listing.destroy!
      redirect_to panel_listings_path, notice: I18n.t("panel.listings.flash.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_listing
      @listing = current_user.listings.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def listing_params
      params.require(:listing).permit(:name, :price, :description, :active, :category_id)
    end

    def set_listings
      @listings = current_user.listings.all
      @listings = @listings.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @listings = @listings.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name, :price, :description, :active).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: current_user.listings.all if params[:items] == "all"
    end
  end
end
