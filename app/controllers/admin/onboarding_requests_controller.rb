module Admin
  class OnboardingRequestsController < Admin::ApplicationController
    include Pagy::Method

    before_action :set_onboarding_request, only: %i[show]
    before_action :set_onboarding_requests, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/onboarding_requests
    def index
      @pagy, @onboarding_requests = pagy(@onboarding_requests)
    end

    # GET /admin/onboarding_requests/search.json
    def search
      @onboarding_requests = params[:items].present? ? base_scope.filter_by_id(params[:items]) : base_scope

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/onboarding_requests/1
    def show
    end

    private

    def base_scope
      current_neighborhood_association.onboarding_requests.where.not(status: "draft")
    end

    def set_onboarding_request
      @onboarding_request = base_scope.find(params[:id])
    end

    def set_onboarding_requests
      @onboarding_requests = base_scope.includes(:user, :identity_verification_request, :residence_verification_request)
      @onboarding_requests = @onboarding_requests.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params[:sort_column].present?
      filter_params.each { |attribute, value| @onboarding_requests = @onboarding_requests.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :status).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: base_scope if params[:items] == "all"
    end
  end
end
