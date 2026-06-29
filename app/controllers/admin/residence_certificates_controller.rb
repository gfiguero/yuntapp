module Admin
  class ResidenceCertificatesController < ApplicationController
    include Pagy::Method

    before_action :set_residence_certificate, only: :show
    before_action :set_residence_certificates, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # BR-064 + BR-077: el flujo de certificados es exclusivamente
    # pending_payment → paid → issued. La emisión es automática (BR-062),
    # iniciada por el pago confirmado vía MercadoPago. El admin solo tiene
    # acceso de lectura — no puede crear, editar ni eliminar certificados.

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

    private

    def set_residence_certificate
      @residence_certificate = current_neighborhood_association.residence_certificates.find(params[:id])
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
