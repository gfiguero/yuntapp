module Admin
  class ListingsController < ApplicationController
    include Pagy::Method

    before_action :set_listing, only: %i[show edit update delete destroy]
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
      scope = current_neighborhood_association.listings
      @listings = params[:items].present? ? scope.filter_by_id(params[:items]) : scope

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/listings/1
    def show
    end

    # GET /admin/listings/1/edit
    def edit
    end

    # PATCH/PUT /admin/listings/1
    def update
      if @listing.update(listing_params)
        redirect_to admin_listing_path(@listing), notice: I18n.t("admin.listings.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/listings/1/delete
    def delete
    end

    # DELETE /admin/listings/1
    # BR-100: ver Panel::ListingsController#destroy — el historial de pago se
    # preserva retirando la publicación de la vitrina.
    def destroy
      if @listing.ever_paid?
        @listing.withdraw!
        redirect_to admin_listings_path, notice: I18n.t("admin.listings.flash.withdrawn"), status: :see_other, format: :html
      else
        @listing.destroy!
        redirect_to admin_listings_path, notice: I18n.t("admin.listings.flash.destroyed"), status: :see_other, format: :html
      end
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    # BR-007: el admin solo gestiona las publicaciones de su junta (las de sus usuarios).
    def set_listing
      @listing = current_neighborhood_association.listings.find(params[:id])
    end

    # Only allow a list of trusted parameters through. Sin :user_id: el admin no puede
    # reasignar una publicación a otro usuario (BR-007).
    def listing_params
      params.require(:listing).permit(:name, :price, :description, :active, :category_id)
    end

    def set_listings
      @listings = current_neighborhood_association.listings
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
      render json: current_neighborhood_association.listings if params[:items] == "all"
    end
  end
end
