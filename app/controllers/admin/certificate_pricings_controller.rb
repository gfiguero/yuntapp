module Admin
  class CertificatePricingsController < Admin::ApplicationController
    # GET /admin/certificate_pricings
    def index
      @certificate_pricings = current_neighborhood_association
        .certificate_pricings
        .order(effective_from: :desc)
      @current_pricing = CertificatePricing.current_for(current_neighborhood_association)
    end

    # GET /admin/certificate_pricings/new
    def new
      @certificate_pricing = CertificatePricing.new
    end

    # POST /admin/certificate_pricings
    def create
      @certificate_pricing = CertificatePricing.new(pricing_params)
      @certificate_pricing.assign_attributes(
        neighborhood_association: current_neighborhood_association,
        created_by: current_user,
        effective_from: Time.current,
        effective_to: nil
      )

      if @certificate_pricing.save
        redirect_to admin_certificate_pricings_path,
          notice: I18n.t("admin.certificate_pricings.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def pricing_params
      params.require(:certificate_pricing).permit(:price)
    end
  end
end
