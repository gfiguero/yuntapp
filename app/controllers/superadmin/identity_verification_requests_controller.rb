module Superadmin
  class IdentityVerificationRequestsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_identity_verification_request, only: %i[show edit update delete destroy]
    before_action :set_identity_verification_requests, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    def index
      @pagy, @identity_verification_requests = pagy(@identity_verification_requests)
    end

    def search
      @identity_verification_requests = params[:items].present? ? IdentityVerificationRequest.filter_by_id(params[:items]) : IdentityVerificationRequest.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    def show
    end

    def edit
    end

    def update
      if @identity_verification_request.update(identity_verification_request_params)
        redirect_to superadmin_identity_verification_request_path(@identity_verification_request), notice: I18n.t("superadmin.identity_verification_requests.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def delete
    end

    def destroy
      @identity_verification_request.destroy!
      redirect_to superadmin_identity_verification_requests_path, notice: I18n.t("superadmin.identity_verification_requests.flash.destroyed"), status: :see_other, format: :html
    end

    private

    def set_identity_verification_request
      @identity_verification_request = IdentityVerificationRequest.find(params[:id])
    end

    def identity_verification_request_params
      params.require(:identity_verification_request).permit(:status, :rejection_reason)
    end

    def set_identity_verification_requests
      @identity_verification_requests = IdentityVerificationRequest.all
      @identity_verification_requests = @identity_verification_requests.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @identity_verification_requests = @identity_verification_requests.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :status, :user_id, :first_name, :last_name, :run).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: IdentityVerificationRequest.all if params[:items] == "all"
    end
  end
end
