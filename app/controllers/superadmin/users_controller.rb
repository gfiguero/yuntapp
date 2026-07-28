module Superadmin
  class UsersController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_user, only: %i[show edit update block confirm_block unblock]
    before_action :set_users, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /superadmin/users
    def index
      @pagy, @users = pagy(@users)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /superadmin/users/search.json
    def search
      @users = params[:items].present? ? User.filter_by_id(params[:items]) : User.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /superadmin/users/1
    def show
    end

    # GET /superadmin/users/1/edit
    def edit
    end

    # PATCH/PUT /superadmin/users/1
    def update
      if @user.update(user_params)
        redirect_to superadmin_user_path(@user), notice: I18n.t("superadmin.users.flash.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /superadmin/users/1/block
    def block
    end

    # PATCH /superadmin/users/1/confirm_block
    # BR-100: bloquear no destruye la cuenta; la deja inactiva (login bloqueado) y el
    # usuario no puede reactivarla por sí mismo. Un superadmin no es bloqueable.
    def confirm_block
      if @user.superadmin?
        redirect_to superadmin_user_path(@user), alert: I18n.t("superadmin.users.flash.cannot_block_superadmin")
        return
      end

      @user.block!(by: current_user, reason: params[:block_reason])
      redirect_to superadmin_user_path(@user), notice: I18n.t("superadmin.users.flash.blocked"), status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :block, status: :unprocessable_content
    end

    # PATCH /superadmin/users/1/unblock
    def unblock
      @user.unblock!
      redirect_to superadmin_user_path(@user), notice: I18n.t("superadmin.users.flash.unblocked"), status: :see_other
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:admin, :superadmin, :neighborhood_association_id)
    end

    def set_users
      @users = User.all
      @users = @users.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @users = @users.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :email).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: User.all if params[:items] == "all"
    end
  end
end
