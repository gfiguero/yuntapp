module Superadmin
  class OnboardingRequestsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_onboarding_request, only: %i[show edit update delete destroy]
    before_action :set_onboarding_requests, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    def index
      @pagy, @onboarding_requests = pagy(@onboarding_requests)
    end

    def search
      @onboarding_requests = params[:items].present? ? OnboardingRequest.filter_by_id(params[:items]) : OnboardingRequest.all

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
      if @onboarding_request.update(onboarding_request_params)
        redirect_to superadmin_onboarding_request_path(@onboarding_request), notice: I18n.t("superadmin.onboarding_requests.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def delete
    end

    def destroy
      @onboarding_request.destroy!
      redirect_to superadmin_onboarding_requests_path, notice: I18n.t("superadmin.onboarding_requests.flash.destroyed"), status: :see_other, format: :html
    end

    private

    def set_onboarding_request
      @onboarding_request = OnboardingRequest.find(params[:id])
    end

    def onboarding_request_params
      params.require(:onboarding_request).permit(:status)
    end

    def set_onboarding_requests
      @onboarding_requests = OnboardingRequest.all
      @onboarding_requests = @onboarding_requests.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @onboarding_requests = @onboarding_requests.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :status, :user_id, :neighborhood_association_id).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: OnboardingRequest.all if params[:items] == "all"
    end
  end
end
