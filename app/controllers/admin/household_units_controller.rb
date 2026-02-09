module Admin
  class HouseholdUnitsController < ApplicationController
    include Pagy::Method

    before_action :set_household_unit, only: %i[show edit update delete destroy]
    before_action :set_household_units, only: :index
    before_action :disabled_pagination
    after_action { response.headers.merge!(@pagy.headers_hash) if @pagy }

    # GET /admin/household_units
    def index
      @pagy, @household_units = pagy(@household_units)

      respond_to do |format|
        format.html
        format.json
      end
    end

    # GET /admin/household_units/search.json
    def search
      @household_units = params[:items].present? ? HouseholdUnit.filter_by_id(params[:items]) : HouseholdUnit.all

      respond_to do |format|
        format.json
        format.turbo_stream
      end
    end

    # GET /admin/household_units/1
    def show
    end

    # GET /admin/household_units/new
    def new
      @household_unit = HouseholdUnit.new
    end

    # GET /admin/household_units/1/edit
    def edit
    end

    # POST /admin/household_units
    def create
      @household_unit = HouseholdUnit.new(household_unit_params)

      if @household_unit.save
        redirect_to admin_household_unit_path(@household_unit), notice: I18n.t("household_unit.message.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/household_units/1
    def update
      if @household_unit.update(household_unit_params)
        redirect_to admin_household_unit_path(@household_unit), notice: I18n.t("household_unit.message.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # GET /admin/household_units/1/delete
    def delete
    end

    # DELETE /admin/household_units/1
    def destroy
      @household_unit.destroy!
      redirect_to admin_household_units_path, notice: I18n.t("household_unit.message.destroyed"), status: :see_other, format: :html
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_household_unit
      @household_unit = current_neighborhood_association.household_units.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def household_unit_params
      params.require(:household_unit).permit(:number, :neighborhood_delegation_id, :address_line_1, :address_line_2, :city, :region, :country, :postal_code, :commune_id)
    end

    def set_household_units
      @household_units = current_neighborhood_association.household_units
      @household_units = @household_units.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
      filter_params.each { |attribute, value| @household_units = @household_units.send(filter_scope(attribute), value) } if filter_params.present?
    end

    def sort_params
      params.permit(:sort_column, :sort_direction)
    end

    def filter_params
      params.permit(:id, :number).reject { |key, value| value.blank? }
    end

    def disabled_pagination
      render json: current_neighborhood_association.household_units if params[:items] == "all"
    end
  end
end
