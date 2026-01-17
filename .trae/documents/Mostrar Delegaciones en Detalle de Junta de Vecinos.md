Modificaré la vista `show` de las Juntas de Vecinos (`NeighborhoodAssociation`) para incluir el listado de sus Delegaciones Vecinales asociadas.

### Plan de Acción:

1.  **Modificar `show.html.erb` de `NeighborhoodAssociation`**:
    *   Mantener la estructura actual para mostrar los datos de la Junta de Vecinos.
    *   Agregar una nueva sección debajo de los datos básicos para listar las Delegaciones Vecinales.
    *   Utilizar un parcial similar a `_table.html.erb` de `NeighborhoodDelegations`, pero adaptado para mostrar solo las delegaciones de *esta* junta (sin necesidad de mostrar la columna "Junta de Vecinos" ya que es redundante en este contexto, o reutilizando el existente si es posible pasando variables locales).
    *   Para una implementación limpia y reusable, renderizaré la colección de delegaciones directamente iterando sobre `@neighborhood_association.neighborhood_delegations`.

2.  **Detalles de la Implementación**:
    *   En `app/views/admin/neighborhood_associations/show.html.erb`, agregaré un contenedor con título "Delegaciones Vecinales".
    *   Dentro, renderizaré una tabla simple que itere sobre `@neighborhood_association.neighborhood_delegations`.
    *   Reutilizaré el partial `app/views/admin/neighborhood_delegations/_neighborhood_delegation_row.html.erb` para mantener consistencia en las filas de la tabla.

3.  **Verificación**:
    *   Asegurarse de que el partial `_neighborhood_delegation_row` funcione correctamente en este contexto (es decir, que tenga acceso a las rutas necesarias, lo cual debería ser cierto ya que usa rutas `admin_neighborhood_delegation_path`).

No se requieren cambios en el controlador ni en el modelo para esta visualización básica, ya que la relación `has_many` ya existe y podemos acceder a las delegaciones a través de la instancia `@neighborhood_association`.