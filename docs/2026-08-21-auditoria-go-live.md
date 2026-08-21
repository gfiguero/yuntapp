# Auditoría pre-go-live — 2026-08-21

**Commit auditado:** `259e22c` (el mismo que corre en producción).
**Método:** cinco auditores en paralelo, con focos distintos, sobre código y sobre producción en solo
lectura. Informes completos en [`docs/auditoria-2026-08-21/`](auditoria-2026-08-21/).
**Alcance:** enfocada en lo que impide abrir la plataforma a vecinos reales. No repite el barrido general
de `2026-07-30-auditoria-profunda.md`.

| Informe | Foco | Crítica | Alta | Media | Baja |
|---|---|---|---|---|---|
| [01-dinero](auditoria-2026-08-21/01-dinero.md) | Flujo del dinero end-to-end | 1 | 8 | 4 | 4 |
| [02-certificados](auditoria-2026-08-21/02-certificados.md) | Ciclo de vida del certificado | 1 | 1 | 0 | 1 |
| [03-privacidad](auditoria-2026-08-21/03-privacidad.md) | Datos personales y aislamiento | 1 | 3 | 5 | 7 |
| [04-multiusuario](auditoria-2026-08-21/04-multiusuario.md) | Usuarios reales que no son el owner | 1 | 3 | 3 | 2 |
| [05-operacion](auditoria-2026-08-21/05-operacion.md) | Infraestructura y pendientes previos | 1 | 2 | 1 | 3 |

Las críticas de 02 y 03 son **el mismo defecto**, encontrado por dos auditores independientes; el de 01
lo encontró por tercera vez desde otro ángulo. Descontando esa convergencia, son **cuatro hallazgos
críticos distintos**.

---

## Los cuatro bloqueadores

Cada uno se verificó a mano antes de publicarse, no solo por el reporte del auditor.

### 1. Las credenciales de MercadoPago son de un usuario de prueba

Ningún vecino real puede pagar. El token de producción responde:

```
email    = test_user_1844981119760716579@testuser.com
nickname = TESTUSER1844981119760716579
tags     = ["user_product_seller", "test_user", "normal"]
site     = MLC
```

Lo que despista es el prefijo: el token empieza con `APP_USR-`, no con `TEST-`, así que parece de
producción. La cuenta está marcada como `test_user` por la propia API de MercadoPago.

Ya estaba anotado como **TASK-011** en el backlog; ahora está confirmado empíricamente.

**Verificado:** consulta a `https://api.mercadopago.com/users/me` con el token de producción.

### 2. El aislamiento entre núcleos familiares está a medias

Un `household_admin` **ve y descarga los certificados de otra familia** que viva en su misma dirección.
El PDF que sirve `download` lleva el RUN sin enmascarar y el domicilio completo.

El PR #159 (`7acc76d`) cerró la **emisión** —`selectable_residencies` y `create` filtran por
`family_group`— pero dejó abiertas la **lectura y la descarga**:

- `Panel::ResidenceCertificatesController#index:13` → `where(household_unit: current_user.household_unit)`
- `set_residence_certificate:97` → idéntico, y alimenta `show` y `download`

Ningún test cubre esas tres acciones, que es exactamente por qué el fix anterior pareció completo.

**Impacto hoy: nulo.** No hay certificados en producción y ningún domicilio tiene más de un núcleo
familiar (verificado: `hu_with_multiple_family_groups: {}`). Se materializa con el primer domicilio
compartido.

**Verificado:** lectura directa del controller, más un test de integración del auditor que descargó el
PDF ajeno con 200 OK.

### 3. Subida de archivos sin límite de tamaño ni de tipo

Ningún adjunto valida nada. Las siete declaraciones `has_many_attached`/`has_one_attached` del proyecto
no tienen validación de `content_type` ni de `byte_size`; la única validación existente
(`directiva_validity_document_attached`) solo comprueba presencia. Los formularios tampoco declaran
`accept=`. No hay límite configurado en el proxy.

Active Storage escribe en el mismo disco que la base SQLite, y **quedan 2,4 GB libres**. Un solo usuario
puede llenar el disco; cuando se llene, SQLite deja de poder escribir y la aplicación cae.

**Verificado:** grep sobre los modelos y los formularios, más `df -h` en el droplet.

### 4. Cero respaldos fuera del droplet

No existe ninguna rutina de backup. La base de datos y **todos los documentos de identidad y
comprobantes de domicilio** viven en un único disco. Si el droplet se pierde, se pierde todo: no hay
copia en ningún otro lado.

Los ocho archivos `.bak-*` que existen se crearon a mano antes de cada deploy y están en el mismo disco
que protegerían.

**Verificado:** `crontab -l` y `/etc/cron.d/` en el droplet — solo tareas del sistema.

---

## Altas que conviene resolver antes de abrir

**Dinero** (detalle en 01):
- Un error HTTP de la API de MercadoPago es indistinguible de "no hay nada que hacer": el webhook
  responde 200 y el pago se pierde para siempre.
- El botón "Pagar" sigue visible con un pago en revisión, y el segundo cobro se traga en silencio:
  doble cobro real, sin detección ni devolución.
- Una reversión se aplica sin verificar que el `payment_id` sea el del pago del recurso.
- **No existe conciliación con MercadoPago.** Si un webhook se pierde, el dinero queda cobrado y el
  certificado nunca avanza. Para siempre, sin que nadie se entere.
- En el pago único de publicaciones, BR-090 valida contra `listing.amount`, que se reescribe con el
  precio vigente mientras hay links de checkout activos.

**Privacidad** (detalle en 03):
- **RUN, nombre, teléfono y domicilio quedan en texto plano en los logs de producción.**
  `filter_parameters` tiene el default de Rails (`:passw, :email, :secret, :token…`) y no incluye
  ninguno de esos campos. Filtra `:certificate` pero no `:run`.
- Un admin de junta puede convertir un RUN arbitrario en el domicilio y los convivientes de esa persona
  en **otra** junta. BR-044 y BR-057 piden avisarle al admin que el RUN ya existe verificado en otra
  junta, pero `Admin::OnboardingReviewsController:22` no solo avisa: carga las residencias con su
  domicilio y su junta. La regla dice "informativo"; la implementación revela bastante más.
- No existe política de privacidad ni consentimiento informado para el tratamiento de datos personales.
  En Chile rige la ley 19.628 y el RUN es dato sensible.

**Usuarios reales** (detalle en 04):
- La página de "reenviar confirmación" es el scaffold de Devise, en inglés y sin estilos — y es el único
  camino de rescate de una cuenta que no confirmó su correo. Hoy hay una cuenta superadmin real
  (`daniela.tobar.g@gmail.com`) exactamente en esa situación.
- La revisión de documentos del admin asume imágenes: un PDF la rompe.
- Ningún `rescue_from` en ningún controller: cualquier excepción muestra el 500 de Rails, en inglés.

**Certificados** (detalle en 02):
- El correo de "certificado emitido" de un dependiente llega **al admin de la junta**, no al jefe de
  hogar que lo pidió y pagó. Causa: `Admin::DependentReviewsController#approve:75` guarda
  `requested_by: current_user` —el admin que aprueba— y `Member#user:35` resuelve el destinatario desde
  ahí. El dato correcto existe: `Panel::DependentsController#create` sí guarda al jefe de hogar en la
  solicitud, y la aprobación lo pisa.

**Operación** (detalle en 05):
- Sin monitoreo de errores ni alertas. No hay Sentry ni equivalente en el `Gemfile`. Todas las alertas
  del flujo de dinero son `Rails.logger` a stdout, que nadie lee.
- Droplet con 458 MB de RAM y **544 MB de swap ya en uso**, antes del primer usuario real. El disco al
  73%, aunque la app solo ocupa 9,8 MB: lo que crece son las imágenes de Docker, no los datos.

---

## Un vacío que no es un bug

**No hay contabilidad del 90% que pertenece a las juntas.** No existe split de pago en MercadoPago, ni
ledger, ni reporte, ni proceso definido para transferirles su parte. Hoy el dinero de todas las juntas
cae en una sola cuenta y no hay forma sistemática de saber cuánto le corresponde a cada una.

BR-004 y BR-085 definen la comisión del 10% y el código la calcula bien, pero el 90% restante existe
solo como un número en una columna. Esto no se resuelve con código en un día: es una decisión de
producto y de operación que conviene tomar **antes** de cobrarle a alguien de verdad, no después.

---

## Estado de los 9 hallazgos Baja pendientes

De la auditoría del 2026-07-30 quedaban nueve. Revisados contra el código actual: **6 siguen vigentes**
(normalización de direcciones, RUN normalizado duplicado ahora en 5 sitios, `external_reference`
malformado sin log, redacción engañosa de BR-136, TOCTOU sin índice único en BR-134, `resolve_identity!`
sin usar `IdentityTransferService`), **1 parcialmente vigente** (`IdentityTransferService` sigue sin test
propio) y **2 quedaron obsoletos** porque la sección "Modelo de Datos" de `CLAUDE.md` que documentaban se
eliminó el 2026-08-02.

Ninguno bloquea el go-live.

---

## Áreas que se revisaron y están limpias

Vale registrarlas para no volver a auditarlas sin motivo:

- Verificación pública `/verify`, vitrina del marketplace, páginas de junta y guía: no exponen datos
  personales de más.
- `urls_expire_in: 5.minutes` y `force_ssl: true` correctamente aplicados (BR-147).
- `panel/dependents` y `panel/household_neighbours`: aislamiento correcto por núcleo familiar.
- El resto del aislamiento entre juntas en `admin/` (BR-007).
- BR-101 (desactivación y bloqueo de cuentas) y BR-093 (email inmutable).
- La superficie de autenticación.
- Variables de entorno y credenciales de producción presentes y correctas (salvo las de MercadoPago,
  que son de prueba — hallazgo 1).
- Jobs recurrentes corriendo sin fallos; proceso de deploy y TLS correctos.

---

## Orden de ataque sugerido

**Antes de aceptar el primer peso de un vecino real:**

1. Credenciales de MercadoPago de producción (bloqueador 1) — sin esto no hay negocio.
2. Aislamiento entre núcleos en `index`/`show`/`download`, con tests (bloqueador 2).
3. Límites de tamaño y tipo en los adjuntos (bloqueador 3).
4. Respaldos automáticos fuera del droplet (bloqueador 4).
5. `filter_parameters` con los campos personales — es una línea y evita seguir escribiendo RUN en los
   logs desde el primer día.
6. Monitoreo de errores, aunque sea el plan gratuito de algún servicio: hoy nadie se entera de nada.

**Antes de crecer más allá de una junta piloto:**

7. Conciliación con MercadoPago y detección de doble cobro.
8. Decidir cómo se le paga su 90% a las juntas.
9. Política de privacidad y consentimiento.
10. Subir los recursos del droplet.
