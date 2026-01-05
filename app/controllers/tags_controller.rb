class TagsController < ApplicationController
  include Pagy::Method

  before_action :set_tag, only: %i[ show edit update delete destroy ]
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

  # GET /tags/new
  def new
    @tag = Tag.new
  end

  # GET /tags/1/edit
  def edit
  end

  # POST /tags
  def create
    @tag = Tag.new(tag_params)

    if @tag.save
      redirect_to @tag, created: I18n.t("tag.message.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /tags/1
  def update
    if @tag.update(tag_params)
      redirect_to @tag, updated: I18n.t("tag.message.updated"), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # GET //tags/1/delete
  def delete
  end

  # DELETE /tags/1
  def destroy
    @tag.destroy!
    redirect_to tags_path, deleted: I18n.t("tag.message.destroyed"), status: :see_other, format: :html
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_tag
    @tag = Tag.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def tag_params
    params.expect(tag: [ :name ])
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
    params.permit(:id, :name).reject { |key, value| value.blank? }
  end

  def disabled_pagination
    render json: Tag.all if params[:items] == "all"
  end
end
