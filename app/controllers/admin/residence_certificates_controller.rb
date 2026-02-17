module Admin
  class ResidenceCertificatesController < ApplicationController
    include Pagy::Method

    before_action :set_residence_certificate, only: %i[show edit update delete destroy approve reject issue]
    before_action :set_residence_certificates, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/residence_certificates
    def index
      @pagy, @residence_certificates = pagy(@residence_certificates)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/residence_certificates/search.json
    def search
      @residence_certificates = params[:items].present? ? ResidenceCertificate.filter_by_id(params[:items]) : ResidenceCertificate.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/residence_certificates/1
    def show
    end

    # GET /admin/residence_certificates/new
    def new
      @residence_certificate = ResidenceCertificate.new
    end

    # GET /admin/residence_certificates/1/edit
    def edit
    end

    # POST /admin/residence_certificates
    def create
      @residence_certificate = ResidenceCertificate.new(residence_certificate_params)

      if @residence_certificate.save
        redirect_to admin_residence_certificate_path(@residence_certificate), notice: I18n.t("admin.residence_certificates.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/residence_certificates/1
    def update
      if @residence_certificate.update(residence_certificate_params)
        redirect_to admin_residence_certificate_path(@residence_certificate), notice: I18n.t("admin.residence_certificates.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/residence_certificates/1/delete
    def delete
    end

    # DELETE /admin/residence_certificates/1
    def destroy
      @residence_certificate.destroy!
      redirect_to admin_residence_certificates_path, notice: I18n.t("admin.residence_certificates.flash.destroyed"), status: :see_other, format: :html
    end

    # PATCH /admin/residence_certificates/1/approve
    def approve
      @residence_certificate.update!(status: "approved", approved_by: current_user)
      redirect_to admin_residence_certificate_path(@residence_certificate), notice: I18n.t("admin.residence_certificates.flash.approved"), status: :see_other
    end

    # PATCH /admin/residence_certificates/1/reject
    def reject
      @residence_certificate.update!(status: "rejected", approved_by: current_user, notes: params[:notes])
      redirect_to admin_residence_certificate_path(@residence_certificate), notice: I18n.t("admin.residence_certificates.flash.rejected"), status: :see_other
    end

    # PATCH /admin/residence_certificates/1/issue
    def issue
      @residence_certificate.generate_folio!
      @residence_certificate.update!(status: "issued", issue_date: Date.current, expiration_date: 6.months.from_now.to_date)
      redirect_to admin_residence_certificate_path(@residence_certificate), notice: I18n.t("admin.residence_certificates.flash.issued"), status: :see_other
    end

    private

    def set_residence_certificate
      @residence_certificate = current_neighborhood_association.residence_certificates.find(params[:id])
    end

    def residence_certificate_params
      params.require(:residence_certificate).permit(:member_id, :household_unit_id, :purpose, :notes)
        .merge(neighborhood_association_id: current_neighborhood_association.id)
    end

    def set_residence_certificates
      @residence_certificates = current_neighborhood_association.residence_certificates
      @residence_certificates = @residence_certificates.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @residence_certificates = @residence_certificates.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :status, :folio).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: current_neighborhood_association.residence_certificates if params[:items] == "all"
    end
  end
end
