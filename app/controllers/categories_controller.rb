class CategoriesController < ApplicationController
  include Pagy::Method

  before_action :set_category, only: %i[show]
  before_action :set_categories, only: :index
  before_action :disabled_pagination
  after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

  # GET /categories
  def index
    @pagy, @categories = pagy(@categories)

    respond_to do |format|
      format.html
      format.json
    end
  end

  # GET /categories/search.json
  def search
    @categories = params[:items].present? ? Category.filter_by_id(params[:items]) : Category.all

    respond_to do |format|
      format.json
      format.turbo_stream
    end
  end

  # GET /categories/1
  def show
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_category
    @category = Category.find(params.expect(:id))
  end

  def set_categories
    @categories = Category.all
    @categories = @categories.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
    filter_params.each { |attribute, value| @categories = @categories.send(filter_scope(attribute), value) } if filter_params.present?
  end

  def sort_params
    params.permit(:sort_column, :sort_direction)
  end

  def filter_params
    params.permit(:id, :name).reject { |key, value| value.blank? }
  end

  def disabled_pagination
    render json: Category.all if params[:items] == "all"
  end
end
