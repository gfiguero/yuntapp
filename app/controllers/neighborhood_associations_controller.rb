class NeighborhoodAssociationsController < ApplicationController
  include Pagy::Method

  before_action :set_neighborhood_association, only: %i[show]
  before_action :set_neighborhood_associations, only: :index
  before_action :disabled_pagination
  after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

  # GET /neighborhood_associations
  def index
    @pagy, @neighborhood_associations = pagy(@neighborhood_associations)

    respond_to do |format|
      format.html
      format.json
    end
  end

  # GET /neighborhood_associations/search.json
  def search
    @neighborhood_associations = params[:items].present? ? NeighborhoodAssociation.filter_by_id(params[:items]) : NeighborhoodAssociation.all

    respond_to do |format|
      format.json
      format.turbo_stream
    end
  end

  # GET /neighborhood_associations/1
  def show
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_neighborhood_association
    @neighborhood_association = NeighborhoodAssociation.find(params.expect(:id))
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
