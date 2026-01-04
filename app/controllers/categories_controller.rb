class CategoriesController < ApplicationController
  include Pagy::Method

  before_action :set_category, only: %i[ show edit update delete destroy ]
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
    @categories = params[:items].present? ? Category.all.filter_by_id(params[:items]) : Category.all

    respond_to do |format|
      format.json
      format.turbo_stream
    end
  end

  # GET /categories/1
  def show
  end

  # GET /categories/new
  def new
    @category = Category.new
  end

  # GET /categories/1/edit
  def edit
  end

  # POST /categories
  def create
    @category = Category.new(category_params)

    if @category.save
      redirect_to @category, created: I18n.t("category.message.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /categories/1
  def update
    if @category.update(category_params)
      redirect_to @category, updated: I18n.t("category.message.updated"), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # GET //categories/1/delete
  def delete
  end

  # DELETE /categories/1
  def destroy
    @category.destroy!
    redirect_to categories_path, deleted: I18n.t("category.message.destroyed"), status: :see_other, format: :html
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_category
    @category = Category.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def category_params
    params.expect(category: [ :name ])
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
