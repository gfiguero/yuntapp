module Admin
  class TagsController < ApplicationController
    include Pagy::Method

    before_action :set_tag, only: %i[show edit update delete destroy]
    before_action :set_tags, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/tags
    def index
      @pagy, @tags = pagy(@tags)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/tags/search.json
    def search
      @tags = params[:items].present? ? Tag.filter_by_id(params[:items]) : Tag.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/tags/1
    def show
    end

    # GET /admin/tags/new
    def new
      @tag = Tag.new
    end

    # GET /admin/tags/1/edit
    def edit
    end

    # POST /admin/tags
    def create
      @tag = Tag.new(tag_params)

      if @tag.save
        redirect_to admin_tag_path(@tag), notice: I18n.t("tag.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/tags/1
    def update
      if @tag.update(tag_params)
        redirect_to admin_tag_path(@tag), notice: I18n.t("tag.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/tags/1/delete
    def delete
    end

    # DELETE /admin/tags/1
    def destroy
      @tag.destroy!
      redirect_to admin_tags_path, notice: I18n.t("tag.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_tag
      @tag = Tag.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def tag_params
      params.require(:tag).permit(:name)
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
end
