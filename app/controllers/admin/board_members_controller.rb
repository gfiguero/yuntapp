module Admin
  class BoardMembersController < ApplicationController
    include Pagy::Method

    before_action :set_board_member, only: %i[show edit update delete destroy]
    before_action :set_board_members, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/board_members
    def index
      @pagy, @board_members = pagy(@board_members)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/board_members/search.json
    def search
      @board_members = params[:items].present? ? BoardMember.filter_by_id(params[:items]) : BoardMember.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/board_members/1
    def show
    end

    # GET /admin/board_members/new
    def new
      @board_member = BoardMember.new
    end

    # GET /admin/board_members/1/edit
    def edit
    end

    # POST /admin/board_members
    def create
      @board_member = BoardMember.new(board_member_params)

      if @board_member.save
        redirect_to admin_board_member_path(@board_member), notice: I18n.t("board_member.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/board_members/1
    def update
      if @board_member.update(board_member_params)
        redirect_to admin_board_member_path(@board_member), notice: I18n.t("board_member.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/board_members/1/delete
    def delete
    end

    # DELETE /admin/board_members/1
    def destroy
      @board_member.destroy!
      redirect_to admin_board_members_path, notice: I18n.t("board_member.message.destroyed"), status: :see_other, format: :html
    end

    private

    def set_board_member
      @board_member = current_neighborhood_association.board_members.find(params[:id])
    end

    def board_member_params
      params.require(:board_member).permit(:member_id, :position, :start_date, :end_date, :active)
        .merge(neighborhood_association_id: current_neighborhood_association.id)
    end

    def set_board_members
      @board_members = current_neighborhood_association.board_members
      @board_members = @board_members.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @board_members = @board_members.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :position, :active).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: current_neighborhood_association.board_members if params[:items] == "all"
    end
  end
end
