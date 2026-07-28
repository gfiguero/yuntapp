# Onboarding de Administración de Junta — Diseño

**Fecha**: 2026-07-27
**Estado**: Spec para revisión
**Autor**: sesión de brainstorming (Arquitecto)

## Resumen

Hoy las juntas de vecinos (`NeighborhoodAssociation`) se crean **directamente** por el
superadmin (solo campo `name`) y los admins se asignan **a mano** editando los flags del
`User` en `/superadmin/users/:id/edit`. No existe ningún flujo por el cual un dirigente
pueda solicitar administrar su junta.

Esta feature agrega un **onboarding de administración**: un dirigente acreditado solicita
administrar una junta (existente o nueva), acredita su cargo y la constitución legal de la
organización, y **solo el staff (superadmin) puede aprobar**. Al aprobar, en una sola
transacción se crea/enlaza la junta y el solicitante queda como **admin + socio + miembro
de directiva**.

Es el análogo institucional del onboarding de residente (UC-002), pero su aprobador es el
staff, no el admin de junta.

## Actores

- **Dirigente acreditado**: usuario registrado con email confirmado que declara un cargo de
  directiva y solicita administrar una junta.
- **Staff (superadmin)**: único rol que aprueba/rechaza la solicitud.
- **Admins vigentes** de una junta ya administrada: son notificados y pueden objetar cuando
  llega una solicitud sobre su junta.

## Decisión de arquitectura

Modelo nuevo **`AdministrationRequest`** (no reutilizar `OnboardingRequest`):

- Los datos son institucionales (junta + RUT + cargo + vigencia de directiva), distintos al
  onboarding de residente.
- Evita contaminar el flujo de residentes con estados/ramas nuevas.
- Reutiliza las **piezas** existentes (validación de RUN/RUT módulo 11, `VerifiedIdentity`,
  `Member`, `BoardMember`, transferencia de identidad por RUN duplicado — ADR-006) sin
  acoplar ambos flujos.

Alternativa descartada: un flag `kind: admin` en `OnboardingRequest` — mezcla dos dominios
y complica cada rama del onboarding actual.

## UC-008 · Onboarding de administración de junta

**Actor**: Dirigente acreditado (usuario registrado con email confirmado)
**Aprobador**: Staff (superadmin) — exclusivo
**Precondición**: UC-001 completado (cuenta con email confirmado); el usuario no es admin de
otra junta (BR-136)

| # | Paso |
|---|------|
| 1 | El dirigente entra a "Administrar mi junta" en el panel |
| 2 | Selecciona su junta del catálogo (región→comuna→junta) o propone una nueva (nombre + comuna) |
| 3 | Ingresa el RUT de la organización y sube el certificado de vigencia de la directiva |
| 4 | Declara su cargo en la directiva (presidente/secretario/tesorero/director) |
| 5 | Ingresa sus datos personales (nombre, apellido, RUN, teléfono, documento de identidad) |
| 6 | Revisa el resumen y envía la solicitud (`draft` → `pending`) |
| 7 | Si la junta ya tiene admin activo, los admins vigentes son notificados y pueden objetar |
| 8 | El staff revisa documentos (RUT + vigencia) y aprueba o rechaza |
| 9 | Al aprobar: se crea/enlaza la junta con su RUT, y se crean `VerifiedIdentity` + `Member(approved)` + `BoardMember` y el `User` pasa a admin — todo transaccional |

**Postcondición**: `AdministrationRequest` en `approved`; `NeighborhoodAssociation` con RUT;
`User` con `admin: true` + `neighborhood_association_id`; `Member(approved)` y `BoardMember`
activos del dirigente en esa junta.

## Reglas de negocio (categoría Administración salvo indicación)

| ID | Categoría | Regla |
|----|-----------|-------|
| BR-122 | Acceso | Solo el staff (superadmin) aprueba/rechaza una solicitud de administración. Ningún admin de junta ni otro rol puede |
| BR-123 | Administración | El solicitante declara su cargo (presidente/secretario/tesorero/director) y adjunta **obligatoriamente** el certificado de vigencia de la directiva y el RUT de la organización. Sin ambos no pasa a `pending` |
| BR-124 | Administración | Precondición: cuenta con email confirmado. Flujo institucional, no auto-registro abierto |
| BR-125 | Administración | Apunta a junta del catálogo (región→comuna→junta) o propone una nueva (nombre + comuna). La junta nueva **no se crea hasta aprobar**; antes no es visible ni seleccionable por residentes |
| BR-126 | Administración | Estados: `draft` → `pending` → `approved`/`rejected`; `cancelled` disponible en `pending` (espejo de `OnboardingRequest`) |
| BR-127 | Identidad | Datos del dirigente con las mismas normalizaciones/validaciones del residente: RUN+DV (BR-010/011), teléfono +569 (BR-013), nombres capitalizados (BR-014) |
| BR-128 | Integridad | Aprobación transaccional: crea/enlaza `NeighborhoodAssociation` (con RUT); **reutiliza** `VerifiedIdentity` por RUN si existe (ADR-006 si es de otra cuenta) o la crea; **reutiliza** el `Member` de esa junta si existe, si no crea `Member(approved)`; crea `BoardMember(cargo, start_date hoy, active)`; marca `User` admin + FK. Todo o nada |
| BR-129 | Identidad | Si el RUN pertenece a otra cuenta, aplica transferencia de identidad por RUN duplicado (BR-057–059 / ADR-006) |
| BR-130 | Administración | Junta con admin activo: los admins vigentes son notificados y pueden objetar; el staff decide. La aprobación **agrega co-admin** (BR-052), no reemplaza |
| BR-131 | Administración | Rechazo con motivo obligatorio; queda en historial; el usuario puede duplicar/re-enviar (espejo BR-047–049) |
| BR-132 | Multi-tenant | El admin solo ve/gestiona su junta (BR-007). Su `Member` se crea sin `Residency`/`HouseholdUnit`: no habilita certificados a su nombre hasta hacer onboarding de residencia |
| BR-133 | Administración | Digest diario al staff de solicitudes pendientes (espejo BR-050); el solicitante es notificado en cada transición |
| BR-134 | Administración | Un usuario tiene a lo más **una** solicitud de administración activa (`draft`/`pending`) a la vez |
| BR-135 | Precios | Junta nueva arranca sin `CertificatePricing`/`ListingPricing`; el admin debe definir precio (mín. $1.000 — BR-005/070/084) antes de operar |
| BR-136 | Acceso | Un usuario solo puede administrar **una** junta a la vez (FK único `User.neighborhood_association_id`). Si ya es admin, no puede solicitar otra administración hasta dejar la actual |
| BR-137 | Integridad | **Consecuencia del acoplamiento admin↔socio**: si el dirigente ya era socio activo de **otra** junta, aprobarlo desactiva su `Member` anterior (BR-029) → invalida sus certificados de esa junta (BR-091) y, si era `household_admin`, desactiva en cascada a sus dependientes (BR-099). Si ya era socio de la **misma** junta, se reutiliza sin desactivar nada. El sistema **advierte** al solicitante y al staff de esta consecuencia antes de aprobar |
| BR-138 | Administración | El acceso de admin **no caduca** automáticamente al vencer el período de la directiva (`end_date`). La vigencia queda a criterio del staff/junta (espejo BR-045); la revocación es manual |
| BR-139 | Administración | Junta nueva con nombre+comuna igual a una existente → **advertencia** de posible duplicado al staff (no bloqueo duro); decide el staff |
| BR-140 | Administración | Cargo de directiva ya ocupado por un `BoardMember` activo → **advertencia** al staff; no se desplaza automáticamente al titular vigente |
| BR-119 | Integridad | RUT de la organización **obligatorio**, normalizado + DV módulo 11, **único** entre juntas, almacenado en `NeighborhoodAssociation`. Es la prueba de constitución legal de la junta |
| BR-120 | Certificados | La emisión de certificados (BR-062) y el cobro de publicaciones exigen junta con RUT válido. Una junta no constituida legalmente no puede emitir — hacerlo violaría la ley chilena |
| BR-121 | Integridad | **No puede existir `NeighborhoodAssociation` sin RUT** (columna `NOT NULL`, único, DV válido módulo 11). El RUT **no codifica semántica de entorno**: un RUT en cualquier rango —incluido 70.000.000–99.999.999— puede pertenecer a una organización o persona real, en producción o desarrollo. Las juntas heredadas se regularizan asignándoles un RUT válido; para las juntas demo existentes se usan los 10 RUTs provistos (que son solo RUTs válidos, no un marcador de prueba). Distinguir juntas demo, si se necesita, requiere un marcador explícito aparte del RUT |

## Cambios de modelo de datos

### `AdministrationRequest` (nuevo)
- `user_id` (FK, requerido) — solicitante
- `status` — `draft` | `pending` | `approved` | `rejected` | `cancelled`
- Datos de la junta objetivo:
  - `neighborhood_association_id` (FK, nullable) — si apunta a junta existente
  - `region_id`, `commune_id` — selección geográfica
  - `proposed_association_name` (string, nullable) — si propone junta nueva
  - `organization_rut` (string, requerido para pasar a `pending`) — RUT de la organización
- Datos del dirigente:
  - `position` (string) — cargo declarado (POSITIONS de `BoardMember`)
  - `first_name`, `last_name`, `run`, `phone` — normalizados como en el residente
- Trazabilidad: `reviewed_by_id` (User staff), `reviewed_at`, `rejection_reason`
- Attachments (Active Storage): `directiva_validity_document` (vigencia de directiva),
  `identity_documents` (del dirigente)

### `NeighborhoodAssociation` (modificado)
- `rut` (string, **NOT NULL**, único) — RUT de la organización (BR-119/BR-121)
- Validación RUT (módulo 11) reutilizando la lógica de `RunValidator` (extraer validador
  compartido o `RutValidator`)
- El RUT **no** codifica entorno: no se deriva ningún `test?` del rango del RUT (BR-121).
  Si más adelante se necesita distinguir juntas demo, se hará con un marcador explícito
  (p. ej. una columna dedicada seteada por el seeder), no por el RUT

### Backfill de juntas heredadas (migración + seed)
Toda junta existente debe recibir un RUT antes de activar `NOT NULL`. Las juntas demo
existentes se rellenan con estos RUTs válidos (DV verificado). Son solo RUTs válidos para
poblar datos existentes; no marcan "prueba" ni por su rango ni por su uso:

```
70.207.956-K   71.724.860-0   74.426.693-9   83.014.859-0   83.312.584-2
86.429.665-3   91.399.989-4   91.750.662-0   94.600.037-K   96.807.455-5
```

Estrategia expand-contract: (1) agregar `rut` nullable + único, (2) backfill de las juntas
existentes con los RUTs de prueba, (3) hacer `NOT NULL`.

## Transacción de aprobación (staff)

Al aprobar una `AdministrationRequest` (todo o nada — BR-128):

1. **Junta**: si `neighborhood_association_id` presente, enlazar; si no, crear
   `NeighborhoodAssociation(name: proposed_association_name, commune:, rut: organization_rut)`.
   Si la junta existente no tiene RUT (legacy), guardar el aportado (regularización);
   si ya tiene RUT y difiere, el staff resuelve (BR-119).
2. **Identidad**: reutilizar `VerifiedIdentity` por RUN o crearla. Si el RUN pertenece a
   otra cuenta, transferir identidad (ADR-006 / BR-129).
3. **Membresía**: reutilizar `Member` del par (identidad, junta) si existe; si no, crear
   `Member(approved)`. Si el dirigente tenía `Member` activo en **otra** junta → pasa a
   `inactive` (BR-029/BR-137) con las cascadas asociadas (BR-091/BR-099).
4. **Directiva**: crear `BoardMember(member:, position:, start_date: hoy, active: true)`.
5. **Acceso**: `user.update!(admin: true, neighborhood_association_id: junta.id)`.

## Notificaciones

- **Al solicitante**: en cada transición (`pending` recibido, `approved`, `rejected`).
- **Al staff**: digest diario de solicitudes de administración pendientes (espejo BR-050 /
  `OnboardingRemindersJob`).
- **A los admins vigentes** de una junta ya administrada: aviso al llegar una solicitud
  sobre su junta, con posibilidad de objetar (BR-130).

## Huecos analizados y resueltos

1. **Admin acoplado a socio vs BR-029/BR-091** → *acoplado con reuso inteligente*: reutiliza
   `Member` si existe; si no, crea y desactiva la membresía anterior con sus consecuencias,
   advertidas antes de aprobar (BR-137).
2. **Un usuario administra ≥2 juntas** → no, una sola (BR-136), coincide con el FK único.
3. **`BoardMember` requiere `Member`** → resuelto por el acoplamiento: el dirigente es socio
   de la junta que administra, por lo que existe/creamos su `Member`.
4. **Solicitante ya socio de la misma junta** → se reutiliza su `Member` (BR-128).
5. **Caducidad de la directiva** → el acceso no auto-caduca (BR-138), revocación manual.
6. **Junta/cargo duplicados** → advertencias al staff, no bloqueo (BR-139/BR-140).
7. **`VerifiedIdentity` "inactiva"** → aclaración: la identidad es global, única por RUN y
   nunca se duplica ni se inactiva; lo que se inactiva es el `Member` (BR-137).
8. **Junta sin RUT** → imposible (BR-121); backfill de juntas existentes con RUTs válidos.
   El RUT no codifica entorno: cualquier rango puede ser real, en prod o dev.

## Fuera de alcance

- **Visibilidad de juntas sin admin para residentes**: hoy una junta sin admin activo no
  tiene quién apruebe onboardings de residentes. Es un hueco **preexistente**; no se aborda
  aquí. La junta permanece visible como está hoy.
- **Modelo admin↔junta muchos-a-muchos**: descartado (BR-136 fija una junta por admin).
- **Revocación/relevo de admin** (flujo para quitar un admin): fuera de alcance; hoy sigue
  siendo acción manual del staff.
- **Expiración automática por vigencia de directiva**: descartada (BR-138).

## Preguntas abiertas

- ¿El `AdministrationRequest` debe soportar "duplicar" una solicitud rechazada (como BR-049)
  desde el primer release o en una iteración posterior?
- Si se necesita distinguir juntas demo de reales (p. ej. para reportería), ¿se agrega un
  marcador explícito (columna dedicada seteada por el seeder)? No se deriva del RUT.
