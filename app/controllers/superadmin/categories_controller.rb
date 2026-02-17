module Superadmin
  class CategoriesController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_category, only: %i[show edit update delete destroy]
    before_action :set_categories, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/categories
    def index
      @pagy, @categories = pagy(@categories)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/categories/search.json
    def search
      @categories = params[:items].present? ? Category.filter_by_id(params[:items]) : Category.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/categories/1
    def show
    end

    # GET /admin/categories/new
    def new
      @category = Category.new
    end

    # GET /admin/categories/1/edit
    def edit
    end

    # POST /admin/categories
    def create
      @category = Category.new(category_params)

      if @category.save
        redirect_to superadmin_category_path(@category), notice: I18n.t("superadmin.categories.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/categories/1
    def update
      if @category.update(category_params)
        redirect_to superadmin_category_path(@category), notice: I18n.t("superadmin.categories.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/categories/1/delete
    def delete
    end

    # DELETE /admin/categories/1
    def destroy
      @category.destroy!
      redirect_to superadmin_categories_path, notice: I18n.t("superadmin.categories.flash.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_category
      @category = Category.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def category_params
      params.require(:category).permit(:name)
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
end
