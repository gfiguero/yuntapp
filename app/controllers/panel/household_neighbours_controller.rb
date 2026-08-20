module Panel
  # BR-042: el `household_admin` puede ver **qué** otros núcleos familiares
  # conviven en su `HouseholdUnit`, en solo lectura, para tener contexto de
  # quiénes comparten la dirección.
  #
  # BR-041 le prohíbe ver a los residentes de esos núcleos, así que esta vista
  # muestra únicamente recuentos: cuántos núcleos hay y cuántas personas tiene
  # cada uno. Ningún nombre, ningún RUN. Es el mismo criterio que fijó el fix de
  # aislamiento (PR #159): entre contexto y aislamiento, gana el aislamiento.
  class HouseholdNeighboursController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!

    # GET /panel/household_neighbours
    def index
      @household_unit = current_user.household_unit
      @family_group = current_user.family_group

      @other_family_groups = FamilyGroup
        .where(household_unit_id: @household_unit.id)
        .where.not(id: @family_group.id)
        .order(:id)

      # Recuento por núcleo, resuelto en una sola consulta agregada: devuelve
      # números, nunca registros de los que se pueda leer un nombre.
      @resident_counts = Residency
        .approved
        .where(family_group_id: @other_family_groups.map(&:id))
        .group(:family_group_id)
        .count
    end

    private

    def ensure_household_admin!
      return if current_user.household_admin?

      redirect_to panel_root_path, alert: I18n.t("panel.dependents.flash.not_household_admin")
    end
  end
end
