module Admin
  class ListingsController < ApplicationController
    include Pagy::Method

    before_action :set_listing, only: %i[ show edit update delete destroy ]
    before_action :set_listings, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/listings
    def index
      @pagy, @listings = pagy(@listings)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/listings/search.json
    def search
      @listings = params[:items].present? ? Listing.new.filter_by_id(params[:items]) : Listing.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/listings/1
    def show
    end

    # GET /admin/listings/new
    def new
      @listing = Listing.new
    end

    # GET /admin/listings/1/edit
    def edit
    end

    # POST /admin/listings
    def create
      @listing = Listing.new(listing_params)

      if @listing.save
        redirect_to admin_listing_path(@listing), notice: I18n.t("listing.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/listings/1
    def update
      if @listing.update(listing_params)
        redirect_to admin_listing_path(@listing), notice: I18n.t("listing.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/listings/1/delete
    def delete
    end

    # DELETE /admin/listings/1
    def destroy
      @listing.destroy!
      redirect_to admin_listings_path, notice: I18n.t("listing.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_listing
      @listing = Listing.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def listing_params
      params.require(:listing).permit(:name, :price, :description, :active, :user_id)
    end

    def set_listings
      @listings = Listing.all
      @listings = @listings.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @listings = @listings.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name, :price, :description, :active, :user_id).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: Listing.all if params[:items] == "all"
    end
  end
end
