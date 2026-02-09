module Superadmin
  class NeighborhoodAssociationsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_neighborhood_association, only: %i[show edit update delete destroy impersonate]
    before_action :set_neighborhood_associations, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/neighborhood_associations
    def index
      @pagy, @neighborhood_associations = pagy(@neighborhood_associations)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/neighborhood_associations/search.json
    def search
      @neighborhood_associations = params[:items].present? ? NeighborhoodAssociation.filter_by_id(params[:items]) : NeighborhoodAssociation.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/neighborhood_associations/1
    def show
    end

    # GET /admin/neighborhood_associations/new
    def new
      @neighborhood_association = NeighborhoodAssociation.new
    end

    # GET /admin/neighborhood_associations/1/edit
    def edit
    end

    # POST /admin/neighborhood_associations
    def create
      @neighborhood_association = NeighborhoodAssociation.new(neighborhood_association_params)

      if @neighborhood_association.save
        redirect_to superadmin_neighborhood_association_path(@neighborhood_association), notice: I18n.t("neighborhood_association.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/neighborhood_associations/1
    def update
      if @neighborhood_association.update(neighborhood_association_params)
        redirect_to superadmin_neighborhood_association_path(@neighborhood_association), notice: I18n.t("neighborhood_association.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/neighborhood_associations/1/delete
    def delete
    end

    def impersonate
      session[:impersonated_neighborhood_association_id] = @neighborhood_association.id
      redirect_to admin_root_path, notice: "Ahora estás administrando #{@neighborhood_association.name}"
    end

    # DELETE /admin/neighborhood_associations/1
    def destroy
      @neighborhood_association.destroy!
      redirect_to superadmin_neighborhood_associations_path, notice: I18n.t("neighborhood_association.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_neighborhood_association
      @neighborhood_association = NeighborhoodAssociation.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def neighborhood_association_params
      params.require(:neighborhood_association).permit(:name)
    end

    def set_neighborhood_associations
      @neighborhood_associations = NeighborhoodAssociation.all
      @neighborhood_associations = @neighborhood_associations.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @neighborhood_associations = @neighborhood_associations.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :name).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: NeighborhoodAssociation.all if params[:items] == "all"
    end
  end
end
