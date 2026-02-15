module Panel
  class HouseholdUnitsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_household_unit, only: [:edit, :update]

    def new
      if current_user.household_unit
        redirect_to edit_panel_household_unit_path(current_user.household_unit)
      else
        @household_unit = HouseholdUnit.new
      end
    end

    def create
      @household_unit = HouseholdUnit.new(household_unit_params)

      if @household_unit.save
        session[:pending_household_unit_id] = @household_unit.id

        redirect_to new_panel_accreditation_path, notice: "Domicilio creado. Ahora completa tu acreditación."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @household_unit.update(household_unit_params)
        redirect_to panel_root_path, notice: "Domicilio actualizado exitosamente."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_household_unit
      @household_unit = current_user.household_unit
      unless @household_unit
        redirect_to new_panel_household_unit_path, alert: "Debes crear un domicilio primero."
      end
    end

    def household_unit_params
      params.require(:household_unit).permit(:number, :address_line_1, :address_line_2, :city, :region, :country, :postal_code, :neighborhood_delegation_id, :commune_id)
    end
  end
end
