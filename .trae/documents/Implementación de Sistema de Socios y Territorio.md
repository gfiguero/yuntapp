Implementaré el sistema de registro de socios y territorio siguiendo esta estructura:

### 1. Nuevos Modelos
Crearé 3 nuevos modelos para reflejar la jerarquía solicitada:
*   **NeighborhoodUnit** (Unidad Vecinal/Calle): Pertenece a una `NeighborhoodAssociation`. Representa las calles o sectores.
    *   Campos: `name` (string), `neighborhood_association_id` (fk).
*   **HouseholdUnit** (Unidad Domiciliaria): Pertenece a una `NeighborhoodUnit`. Representa la vivienda específica.
    *   Campos: `number` (string - para permitir "123" o "123-B"), `neighborhood_unit_id` (fk).
*   **Member** (Socio): Reside en una `HouseholdUnit`.
    *   Campos: `first_name` (string), `last_name` (string), `run` (string - identificador), `phone` (string), `email` (string), `household_unit_id` (fk).

### 2. Relaciones
*   `NeighborhoodAssociation` tendrá `has_many :neighborhood_units`.
*   `NeighborhoodUnit` tendrá `has_many :household_units`.
*   `HouseholdUnit` tendrá `has_many :members`.

### 3. Panel de Administración (Superadmin)
Crearé los controladores y vistas dentro del espacio de nombres `Admin` para gestionar estas entidades:
*   `Admin::NeighborhoodUnitsController`
*   `Admin::HouseholdUnitsController`
*   `Admin::MembersController`

Cada uno incluirá:
*   CRUD completo (Crear, Leer, Actualizar, Eliminar).
*   Búsqueda y paginación (integrado con `Pagy` y lógica existente).
*   Vistas consistentes con el diseño actual del panel de admin.

### 4. Integración
*   Agregaré las nuevas rutas en `config/routes.rb`.
*   Actualizaré el menú lateral del admin para incluir estas nuevas secciones.
*   Agregaré las traducciones correspondientes en `es.yml` para que los nombres se muestren correctamente ("Unidades Vecinales", "Domicilios", "Socios").