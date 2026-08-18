class TagsController < ApplicationController
  include Pagy::Method

  before_action :set_tag, only: %i[show]
  before_action :set_tags, only: :index
  before_action :disabled_pagination
  after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

  # GET /tags
  def index
    @pagy, @tags = pagy(@tags)

    respond_to do |format|
      format.html
      format.json
    end
  end

  # GET /tags/search.json
  def search
    @tags = params[:items].present? ? Tag.filter_by_id(params[:items]) : Tag.all

    respond_to do |format|
      format.json
      format.turbo_stream
    end
  end

  # GET /tags/1
  def show
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_tag
    @tag = Tag.find(params.expect(:id))
  end

  def set_tags
    @tags = Tag.all
    @tags = @tags.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
    filter_params.each { |attribute, value| @tags = @tags.send(filter_scope(attribute), value) } if filter_params.present?
  end

  def sort_params
    params.permit(:sort_column, :sort_direction)
  end

  def filter_params
    params.permit(:id, :name).compact_blank
  end

  def disabled_pagination
    render json: Tag.all if params[:items] == "all"
  end
end
