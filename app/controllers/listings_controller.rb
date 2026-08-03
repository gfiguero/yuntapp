class ListingsController < ApplicationController
  include Pagy::Method

  before_action :set_listing, only: %i[show]
  before_action :set_listings, only: :index
  before_action :disabled_pagination
  after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

  # GET /listings
  def index
    @pagy, @listings = pagy(@listings)

    respond_to do |format|
      format.html
      format.json
    end
  end

  # GET /listings/search.json
  def search
    @listings = params[:items].present? ? published_scope.filter_by_id(params[:items]) : published_scope

    respond_to do |format|
      format.json
      format.turbo_stream
    end
  end

  # GET /listings/1
  def show
  end

  private

  # BR-083/BR-086: la vitrina pública SOLO muestra publicaciones con la
  # habilitación pagada y su vigencia de 30 días al día. Toda publicación nace
  # en `pending_payment`, así que consultar `Listing.all` aquí permitía publicar
  # gratis (y dejaba visibles las vencidas). Esta es la única fuente de listings
  # del controlador público: index, show, search y el bypass de paginación.
  def published_scope
    Listing.published
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_listing
    @listing = published_scope.find(params.expect(:id))
  end

  def set_listings
    @listings = published_scope
    @listings = @listings.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
    filter_params.each { |attribute, value| @listings = @listings.send(filter_scope(attribute), value) } if filter_params.present?
  end

  def sort_params
    params.permit(:sort_column, :sort_direction)
  end

  def filter_params
    params.permit(:id, :name, :price, :description, :active, :user_id).reject { |key, value| value.blank? }
  end

  def disabled_pagination
    render json: published_scope if params[:items] == "all"
  end
end
