module Admin
  class ListingPricingsController < Admin::ApplicationController
    # GET /admin/listing_pricings
    def index
      @listing_pricings = current_neighborhood_association
        .listing_pricings
        .order(effective_from: :desc)
      @current_pricing = ListingPricing.current_for(current_neighborhood_association)
    end

    # GET /admin/listing_pricings/new
    def new
      @listing_pricing = ListingPricing.new
    end

    # POST /admin/listing_pricings
    def create
      @listing_pricing = ListingPricing.new(pricing_params)
      @listing_pricing.assign_attributes(
        neighborhood_association: current_neighborhood_association,
        created_by: current_user,
        effective_from: Time.current,
        effective_to: nil
      )

      if @listing_pricing.save
        redirect_to admin_listing_pricings_path,
          notice: I18n.t("admin.listing_pricings.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def pricing_params
      params.require(:listing_pricing).permit(:price)
    end
  end
end
