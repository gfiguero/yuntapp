module Admin
  class UsersController < ApplicationController
    include Pagy::Method

    before_action :set_user, only: %i[show edit update delete destroy]
    before_action :set_users, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/users
    def index
      @pagy, @users = pagy(@users)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/users/search.json
    def search
      @users = params[:items].present? ? User.where(id: params[:items]) : User.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/users/1
    def show
    end

    # GET /admin/users/new
    def new
      @user = User.new
    end

    # GET /admin/users/1/edit
    def edit
    end

    # POST /admin/users
    def create
      @user = User.new(user_params)

      if @user.save
        redirect_to admin_user_path(@user), notice: I18n.t("user.message.created", default: "User created successfully")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/users/1
    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: I18n.t("user.message.updated", default: "User updated successfully"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/users/1/delete
    def delete
    end

    # DELETE /admin/users/1
    def destroy
      @user.destroy!
      redirect_to admin_users_path, notice: I18n.t("user.message.destroyed", default: "User destroyed successfully"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = current_neighborhood_association.users.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_params
      params.require(:user).permit(:first_name, :last_name, :email, :admin, :password, :password_confirmation).merge(neighborhood_association_id: current_neighborhood_association.id)
    end

    def set_users
      @users = current_neighborhood_association.users
      # Add simple sort if params present, similar to other controllers
      if params[:sort_column].present? && params[:sort_direction].present?
        @users = @users.order("#{params[:sort_column]} #{params[:sort_direction]}")
      end

      # Add simple filter
      if params[:id].present?
        @users = @users.where(id: params[:id])
      end
      if params[:email].present?
        @users = @users.where("email LIKE ?", "%#{params[:email]}%")
      end
    end

    def disabled_pagination
      render json: current_neighborhood_association.users if params[:items] == "all"
    end
  end
end
