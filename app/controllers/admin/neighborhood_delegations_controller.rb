module Admin
  class NeighborhoodDelegationsController < ApplicationController
    include Pagy::Method

    before_action :set_neighborhood_delegation, only: %i[show edit update delete destroy]
    before_action :set_neighborhood_delegations, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/neighborhood_delegations
    def index
      @pagy, @neighborhood_delegations = pagy(@neighborhood_delegations)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/neighborhood_delegations/search.json
    def search
      @neighborhood_delegations = params[:items].present? ? NeighborhoodDelegation.filter_by_id(params[:items]) : NeighborhoodDelegation.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/neighborhood_delegations/1
    def show
    end

    # GET /admin/neighborhood_delegations/new
    def new
      @neighborhood_delegation = NeighborhoodDelegation.new
    end

    # GET /admin/neighborhood_delegations/1/edit
    def edit
    end

    # POST /admin/neighborhood_delegations
    def create
      @neighborhood_delegation = NeighborhoodDelegation.new(neighborhood_delegation_params)

      if @neighborhood_delegation.save
        redirect_to admin_neighborhood_delegation_path(@neighborhood_delegation), notice: I18n.t("neighborhood_delegation.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/neighborhood_delegations/1
    def update
      if @neighborhood_delegation.update(neighborhood_delegation_params)
        redirect_to admin_neighborhood_delegation_path(@neighborhood_delegation), notice: I18n.t("neighborhood_delegation.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/neighborhood_delegations/1/delete
    def delete
    end

    # DELETE /admin/neighborhood_delegations/1
    def destroy
      @neighborhood_delegation.destroy!
      redirect_to admin_neighborhood_delegations_path, notice: I18n.t("neighborhood_delegation.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_neighborhood_delegation
      @neighborhood_delegation = NeighborhoodDelegation.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def neighborhood_delegation_params
      params.require(:neighborhood_delegation).permit(:name, :neighborhood_association_id)
    end

    def set_neighborhood_delegations
      @neighborhood_delegations = NeighborhoodDelegation.all
      @neighborhood_delegations = @neighborhood_delegations.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @neighborhood_delegations = @neighborhood_delegations.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: NeighborhoodDelegation.all if params[:items] == "all"
    end
  end
end
