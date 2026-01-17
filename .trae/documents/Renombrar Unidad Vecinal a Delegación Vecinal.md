Realizaré el cambio de nombre de **NeighborhoodUnit** (Unidad Vecinal) a **NeighborhoodDelegation** (Delegación Vecinal) en todo el sistema.

### Plan de Acción:

1.  **Base de Datos**:
    *   Renombrar la tabla `neighborhood_units` a `neighborhood_delegations`.
    *   Renombrar la columna `neighborhood_unit_id` a `neighborhood_delegation_id` en la tabla `household_units`.

2.  **Modelos**:
    *   Renombrar `NeighborhoodUnit` a `NeighborhoodDelegation` (archivo `app/models/neighborhood_delegation.rb`).
    *   Actualizar referencias en `NeighborhoodAssociation` (`has_many :neighborhood_delegations`).
    *   Actualizar referencias en `HouseholdUnit` (`belongs_to :neighborhood_delegation`).

3.  **Controladores**:
    *   Renombrar `Admin::NeighborhoodUnitsController` a `Admin::NeighborhoodDelegationsController`.
    *   Actualizar todas las variables de instancia, métodos y redirecciones internas.

4.  **Vistas**:
    *   Renombrar directorio `app/views/admin/neighborhood_units` a `app/views/admin/neighborhood_delegations`.
    *   Renombrar archivos parciales (`_neighborhood_unit.html.erb` -> `_neighborhood_delegation.html.erb`, etc.).
    *   Buscar y reemplazar todas las referencias a `neighborhood_unit` dentro de las vistas de `neighborhood_delegations`, `household_units`, `members` y layouts.

5.  **Rutas**:
    *   Actualizar `config/routes.rb` reemplazando `resources :neighborhood_units` por `resources :neighborhood_delegations`.

6.  **Traducciones**:
    *   Actualizar `config/locales/es.yml`: Cambiar `neighborhood_unit` por `neighborhood_delegation` y el texto "Unidad Vecinal" por "Delegación Vecinal".

7.  **Fixtures y Tests**:
    *   Renombrar `test/fixtures/neighborhood_units.yml` a `neighborhood_delegations.yml`.
    *   Actualizar referencias en `test/fixtures/household_units.yml`.
    *   Actualizar tests relacionados si existen.

Este proceso asegura que no queden rastros del nombre antiguo y mantiene la integridad del sistema.