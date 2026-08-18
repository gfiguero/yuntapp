# Yuntapp - Plataforma Vecinal

## Descripcion General

Yuntapp es una plataforma web que digitaliza el certificado de residencia chileno, un trámite que actualmente solo existe de forma presencial en municipalidades. Permite a los residentes solicitar, pagar y descargar su certificado 100% online, mientras las juntas de vecinos verifican identidad y residencia de forma remota antes de emitirlo. El certificado incluye QR, código alfanumérico y URL de verificación pública. Las juntas definen su precio (mínimo $1.000 CLP) y Yuntapp retiene un 10% de comisión por operación. Además incluye gestión de socios, directiva y un marketplace comunitario.

## Objetivo del Producto y Propuesta de Valor

Yuntapp digitaliza el certificado de residencia, un trámite que hoy **solo existe de forma presencial** en las municipalidades de Chile. La propuesta de valor central es:

> **Cualquier residente puede solicitar, pagar y descargar su certificado de residencia desde internet, sin ir a ninguna oficina.**

Las juntas de vecinos son el ente emisor oficial reconocido. El certificado emitido por Yuntapp tiene la misma validez que el presencial porque la junta verifica la identidad y residencia del solicitante antes de aprobar y emitir el documento.

### Diferenciadores clave
- **100% remoto**: Solicitud, pago y descarga sin desplazamiento físico.
- **Verificación documental online**: Los adminsitradores de la junta revisan los documentos de identidad y residencia enviados digitalmente antes de emitir.
- **Certificado con múltiples canales de validación**: El PDF incluye QR code, código alfanumérico y URL pública para verificar autenticidad.
- **Modelo SaaS para juntas**: Cada junta define su precio, Yuntapp opera como plataforma.

---

## Modelo de Negocio

### Precios
- Cada junta de vecinos define libremente el precio de su certificado de residencia.
- **Precio mínimo**: $1.000 CLP por certificado.
- No hay precio máximo definido, pero debe ser razonable para el contexto vecinal chileno.

### Comisión de Yuntapp
- Yuntapp retiene el **10%** del precio cobrado en cada certificado emitido.
- El 90% restante es para la junta de vecinos.
- La comisión cubre los gastos operacionales de la plataforma (hosting, pasarela de pago, soporte).

### Pasarela de Pago
- **MercadoPago** (Checkout Pro) es la pasarela de pago, **implementada** con el SDK oficial `mercadopago-sdk`.
- `MercadopagoService` crea la preference de checkout y valida la firma HMAC del webhook (BR-072). `Panel::PaymentsController` crea la preference y redirige al `init_point` de MP. `Webhooks::MercadopagoController` recibe la notificación, es idempotente (BR-071) y marca el certificado como `paid`.
- El pago debe completarse **antes** de la emisión. Tras confirmarse, el certificado se emite **automáticamente** (BR-062), sin revisión del admin.
- Si el pago falla, es rechazado o reembolsado, el certificado permanece/vuelve a `pending_payment` y no avanza (BR-003, BR-073).
- Credenciales en `config/initializers/mercadopago.rb`: lee `ENV["MERCADOPAGO_ACCESS_TOKEN"]`/`MERCADOPAGO_WEBHOOK_SECRET` o `credentials.mercadopago.{access_token,webhook_secret}`.

---

## Flujo Principal: Certificado de Residencia

Este es el flujo de negocio más importante de la aplicación. Claude Code debe proteger su integridad en todo cambio de código.

```
Socio aprobado
    │
    ▼
Solicita certificado (panel)
    │  Crea ResidenceCertificate con status: pending_payment
    ▼
Paga con MercadoPago
    │  status → paid (webhook de MercadoPago confirma)
    ▼
Sistema genera automáticamente PDF con folio único + código de validación
    │  status → issued
    ▼
Socio descarga el PDF desde su panel
```

> El admin verificó la identidad y domicilio una sola vez en el onboarding. Los certificados no requieren revisión adicional — se emiten automáticamente tras el pago (BR-062).

### Estados de ResidenceCertificate
| Estado | Descripción |
|--------|-------------|
| `pending_payment` | Solicitud creada, esperando pago |
| `paid` | Pago confirmado por MercadoPago, emisión automática en proceso |
| `issued` | PDF generado y disponible para descarga |

> **REGLA CRÍTICA**: Nunca emitir un certificado sin que el pago esté confirmado (`paid`). No existen estados `approved` ni `rejected` en el flujo de certificados (BR-064).

### Código de Validación del Certificado
El PDF del certificado debe incluir **tres canales de validación simultáneos**:
1. **QR Code**: Apunta a la URL pública de verificación.
2. **Código alfanumérico**: Código único legible (ej: `CR-00042-X7K9`), útil para verificación telefónica.
3. **URL pública**: `https://yuntapp.cl/verify/{token}` — página accesible sin login que muestra la validez del certificado.

La URL pública muestra: nombre del titular, RUN, dirección, junta emisora, fecha de emisión, fecha de vencimiento y estado (válido/inválido/vencido).

---

## Casos de Uso

Cada caso de uso documenta el flujo ideal (happy path). Claude Code debe respetar estas precondiciones y postcondiciones al implementar cualquier feature relacionada. Agregar nuevos casos de uso con el siguiente ID disponible (`UC-XXX`).

---

### UC-001 · Registro de residente
**Actor**: Visitante sin cuenta
**Precondición**: Ninguna

| # | Paso |
|---|------|
| 1 | El visitante accede a la página de registro |
| 2 | Ingresa email y contraseña |
| 3 | Confirma su email mediante el enlace enviado |
| 4 | Es redirigido al panel con instrucciones para iniciar el onboarding |

**Postcondición**: Usuario con cuenta activa, sin asociación ni identidad verificada.

---

### UC-002 · Onboarding: convertirse en socio
**Actor**: Usuario registrado sin socio activo
**Precondición**: UC-001 completado

| # | Paso |
|---|------|
| 1 | Selecciona región, comuna y junta de vecinos |
| 2 | Ingresa nombre, apellido, RUN y teléfono; sube documentos de identidad |
| 3 | Selecciona su delegación vecinal o ingresa dirección manual |
| 4 | Revisa el resumen y envía la solicitud |
| 5 | El admin de la junta recibe la solicitud en su panel |
| 6 | El admin verifica los documentos y aprueba la solicitud |
| 7 | El sistema crea el `Member` activo y notifica al residente |

**Postcondición**: Usuario con `OnboardingRequest` en estado `approved` y `Member` activo vinculado a una `HouseholdUnit`.

---

### UC-003 · Solicitud de certificado de residencia
**Actor**: Socio aprobado (residente con `Member` activo)
**Precondición**: UC-002 completado — `OnboardingRequest` en `approved`

| # | Paso |
|---|------|
| 1 | El socio accede a "Solicitar certificado" en su panel |
| 2 | Selecciona el propósito del certificado (ej: trámite bancario, arriendo) |
| 3 | El sistema muestra el precio definido por la junta y la descripción del certificado |
| 4 | El socio confirma la solicitud |
| 5 | El sistema crea el `ResidenceCertificate` en estado `pending_payment` |
| 6 | El socio es redirigido al flujo de pago (UC-004) |

**Postcondición**: `ResidenceCertificate` creado en estado `pending_payment`.

---

### UC-004 · Pago del certificado
**Actor**: Socio aprobado con solicitud en `pending_payment`
**Precondición**: UC-003 completado

| # | Paso |
|---|------|
| 1 | El socio es redirigido a MercadoPago con el monto del certificado |
| 2 | Completa el pago con su medio de pago preferido |
| 3 | MercadoPago envía webhook de confirmación a Yuntapp |
| 4 | El sistema actualiza el `ResidenceCertificate` a estado `paid` |
| 5 | El sistema registra el `payment_id`, el `amount` pagado y calcula la `platform_fee` (10%) |
| 6 | El admin de la junta recibe notificación de nueva solicitud pagada para revisar |

**Postcondición**: `ResidenceCertificate` en estado `paid`, visible para el admin de la junta.

---

### UC-005 · Emisión automática del certificado
**Actor**: Sistema (automático tras confirmación de pago)
**Precondición**: UC-004 completado — certificado en estado `paid`

| # | Paso |
|---|------|
| 1 | El sistema recibe confirmación de pago de MercadoPago |
| 2 | Genera el folio único (`CR-{association_id}-{sequence}`) |
| 3 | Genera el `validation_token` (UUID) y el `validation_code` (alfanumérico legible) |
| 4 | Genera el PDF con los datos del certificado, QR, código y URL de verificación |
| 5 | El certificado pasa a estado `issued` y el socio recibe notificación |

> No interviene el admin. La identidad y domicilio ya fueron verificados en el onboarding (BR-062).

**Postcondición**: `ResidenceCertificate` en estado `issued` con PDF generado y código de validación activo.

---

### UC-006 · Descarga del certificado
**Actor**: Socio aprobado con certificado emitido
**Precondición**: UC-005 completado — certificado en estado `issued`

| # | Paso |
|---|------|
| 1 | El socio accede a "Mis certificados" en su panel |
| 2 | Ve el certificado emitido con folio, fecha de emisión y fecha de vencimiento |
| 3 | Descarga el PDF |
| 4 | El PDF contiene: datos del titular, junta emisora, propósito, QR, código alfanumérico y URL de verificación |

**Postcondición**: El socio tiene el PDF descargado. El certificado permanece disponible para descargas futuras.

---

### UC-007 · Verificación pública del certificado
**Actor**: Cualquier persona (sin login requerido)
**Precondición**: Tener el código alfanumérico, QR, o URL del certificado

| # | Paso |
|---|------|
| 1 | El verificador accede a `yuntapp.cl/verify/{token}` o escanea el QR o ingresa el código alfanumérico |
| 2 | El sistema busca el certificado por token o código |
| 3 | Muestra: nombre del titular, RUN (parcialmente oculto), junta emisora, propósito, fecha de emisión, fecha de vencimiento y estado |
| 4 | El estado se muestra como: **Válido**, **Vencido**, o **No válido** (titular desactivado por la junta — BR-091). Los certificados no se anulan individualmente; pierden validez cuando la junta desactiva al socio |

**Postcondición**: El verificador obtiene confirmación de la autenticidad del certificado sin necesidad de contactar a la junta.

---

### UC-008 · Onboarding de administración de junta
**Actor**: Dirigente acreditado (usuario registrado con email confirmado)
**Aprobador**: Staff (superadmin) — exclusivo
**Precondición**: UC-001 completado (cuenta con email confirmado); el usuario no es admin de otra junta (BR-136)

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

**Postcondición**: `AdministrationRequest` en `approved`; `NeighborhoodAssociation` con RUT; `User` con `admin: true` + `neighborhood_association_id`; `Member(approved)` y `BoardMember` activos del dirigente en esa junta.

---

## Reglas de Negocio

Estas reglas deben respetarse en cualquier implementación. Si una tarea entra en conflicto con alguna de ellas, consultar antes de implementar.

Claude Code debe agregar una fila a esta tabla cada vez que descubra o acuerde una nueva regla durante el desarrollo. Usar el siguiente ID disponible en la categoría correspondiente. No renumerar reglas existentes; si una regla queda obsoleta, marcarla como `[RETIRADA]` en la descripción.

| ID | Categoría | Regla |
|----|-----------|-------|
| BR-001 | Acceso | Solo socios con `onboarding_request` en estado `approved` y `member` activo pueden solicitar certificados |
| BR-002 | Pagos | No mostrar la solicitud al admin hasta que MercadoPago confirme el pago (status `paid`) |
| BR-003 | Pagos | Si el pago falla o es rechazado, la solicitud permanece en `pending_payment` sin avanzar |
| BR-004 | Comisión | Yuntapp retiene el 10% de cada certificado emitido. Esta comisión es invariable y no puede modificarse por asociación |
| BR-005 | Precios | El precio mínimo por certificado es $1.000 CLP. Validar en modelo y en UI |
| BR-006 | Integridad | El folio `CR-{association_id}-{sequence}` no puede cambiar de formato. Es el identificador oficial |
| BR-007 | Multi-tenant | Un admin solo puede ver y gestionar datos de su propia junta. El superadmin puede ver todo. Enforcement agregado 2026-08-02: `BoardMember` valida que el `member` pertenezca a la junta del cargo. `member_id` viaja por strong params y el `<select>` acotado del formulario es solo defensa de cliente, así que un POST manipulado colaba un socio ajeno en la directiva y filtraba su nombre y RUN en las vistas de directiva, incluida la pública de la junta |
| BR-008 | Integridad | Una vez en estado `issued`, el certificado es inmutable. Para corregir errores se emite uno nuevo (no existe rechazo de certificados — BR-064) |
| BR-009 | Validación | La URL pública de verificación debe responder indefinidamente, incluso para certificados vencidos (mostrar "vencido", no 404) |
| BR-010 | Normalización | El RUN se normaliza antes de validar: eliminar puntos y espacios, convertir a mayúsculas, insertar guión antes del dígito verificador (ej: `12.345.678-k` → `12345678-K`) |
| BR-011 | Identidad | El dígito verificador del RUN debe ser válido según el algoritmo módulo 11 chileno. Rechazar RUN con dígito incorrecto |
| BR-012 | Identidad | El RUN es único en `verified_identities`. No pueden existir dos identidades verificadas con el mismo RUN |
| BR-013 | Normalización | El teléfono se normaliza a formato `+569XXXXXXXX`. Si ingresa `9XXXXXXXX` (9 dígitos), se agrega `+56` automáticamente |
| BR-014 | Normalización | Los nombres se normalizan: primera letra de cada palabra en mayúscula, resto en minúsculas, sin espacios extras |
| BR-015 | Onboarding | El socio debe aceptar los términos (`terms_accepted_at` presente) para enviar la solicitud de onboarding |
| BR-016 | Onboarding | Al cambiar de región se resetean comarca y asociación. Al cambiar de comuna se resetea la asociación (cascada) |
| BR-017 | Onboarding | El envío de onboarding es atómico: `OnboardingRequest`, `IdentityVerificationRequest` y `ResidenceVerificationRequest` pasan a `pending` juntos o ninguno |
| BR-018 | Onboarding | Al reiniciar el onboarding se desactiva el `Member` activo (`deactivate!`, nunca se destruye — BR-100) y se **cancela** la solicitud pendiente. Enforcement corregido 2026-07-31: `Panel::OnboardingController#restart` hacía `destroy` sobre `current_onboarding_request`, que abarca `draft` **y** `pending`, borrando en cascada (`dependent: :destroy`) la solicitud en revisión junto con su `IdentityVerificationRequest` y su `ResidenceVerificationRequest`. Ahora una solicitud `pending` pasa a `cancelled` (datos preservados y duplicables — BR-048/BR-049/BR-051) y solo el borrador, que nunca se envió, se descarta |
| BR-019 | Residencia | Para completar el paso de domicilio: se requiere `neighborhood_delegation_id` O `street_name`, no pueden ambos estar vacíos |
| BR-020 | Residencia | El número de vivienda (`number`) es siempre obligatorio en el domicilio |
| BR-021 | Residencia | El primer residente aprobado de un domicilio recibe `household_admin: true` en su `Residency`. Los siguientes no |
| BR-022 | Acceso | Solo el `household_admin` del domicilio puede solicitar certificados y agregar nuevos miembros al hogar |
| BR-023 | Certificados | Los certificados vencen 30 días después de la fecha de emisión (`issue_date + 30.days`). Plazo legal para certificados emitidos por juntas de vecinos — actualizado 2026-07-23 (antes era 6 meses; los certificados ya emitidos conservan su `expiration_date` original) |
| BR-024 | Integridad | La aprobación del onboarding es transaccional: crea `VerifiedIdentity`, `VerifiedResidence`, `HouseholdUnit`, `Residency` y `Member` en una sola transacción. Si algo falla, se revierte todo. Enforcement extendido 2026-08-02 al alta manual de socios (`Admin::MembersController#create/update`): la `VerifiedIdentity` se guardaba fuera de transacción, así que un fallo del `Member` la dejaba huérfana — una identidad "verificada" materializada sin socio ni verificación documental (BR-044). El socio nace `pending` y con `requested_by` para dejar registrado qué admin lo dio de alta |
| BR-025 | Integridad | Al rechazar un `OnboardingRequest`, se rechazan en cascada su `IdentityVerificationRequest` y `ResidenceVerificationRequest` |
| BR-026 | Acceso | Un `Member` rechazado puede re-enviar su solicitud cambiando el estado de vuelta a `pending` |
| BR-027 | Certificados | Un certificado de residencia se vincula obligatoriamente a un `Member` + `HouseholdUnit` + `NeighborhoodAssociation` |
| BR-028 | Multi-tenant | El admin solo ve solicitudes de onboarding en estado `pending` o posterior. Las solicitudes en `draft` son invisibles para el admin |
| BR-029 | Acceso | Un usuario solo puede ser socio activo de una junta a la vez. Al unirse a una nueva junta, el `Member` anterior pasa a estado `inactive` (nunca se destruye). El historial de certificados e identidad se conserva |
| BR-030 | Integridad | El estado `inactive` en `Member` indica que el socio ya no pertenece activamente a esa junta, pero sus registros históricos (certificados, residencias) permanecen intactos y auditables |
| BR-031 | Onboarding | El cambio de dirección dentro de la misma junta requiere reinicio completo del onboarding. El `Member` anterior pasa a `inactive` y el socio debe completar el flujo de nuevo para que el admin verifique la nueva dirección |
| BR-032 | Acceso | El `household_admin` es el único residente del domicilio que tiene cuenta de usuario (`User` con login). Los demás residentes del domicilio son **residentes dependientes**: registrados por el `household_admin` mediante RUN, sin cuenta propia en el sistema |
| BR-033 | Acceso | Los residentes dependientes no pueden iniciar sesión ni solicitar certificados. Solo el `household_admin` opera en nombre del domicilio |
| BR-034 | Residencia | Si el `household_admin` abandona el domicilio (reinicia onboarding o se va a otra junta), los residentes dependientes quedan desvinculados. No se migran automáticamente al nuevo `household_admin` |
| BR-035 | Onboarding | Para que un domicilio tenga un nuevo `household_admin`, ese residente debe hacer su propio onboarding completo. Una vez aprobado, vuelve a registrar a los residentes dependientes del domicilio |
| BR-036 | Acceso | El admin de la junta puede desactivar manualmente a cualquier `household_admin` o residente dependiente desde el panel de administración, registrando obligatoriamente el motivo de desactivación |
| BR-037 | Integridad | Al desactivar un `household_admin`, todos sus residentes dependientes quedan desactivados en cascada automáticamente |
| BR-038 | Integridad | La desactivación manual no elimina registros. El `Member` pasa a estado `inactive` conservando el historial y el motivo de desactivación. Las `Residency` no cambian de estado (no existe `inactive` en `Residency`); el corte de acceso se aplica exigiendo `Member` aprobado (BR-091) |
| BR-039 | Onboarding | Tras la desactivación de un `household_admin`, cualquier nuevo residente puede hacer onboarding en ese domicilio siguiendo el flujo normal, sin pasos adicionales |
| BR-040 | Residencia | Un `HouseholdUnit` (dirección física) puede contener múltiples `FamilyGroup`, cada uno representando un núcleo familiar distinto que convive en esa dirección (ej: dos familias en la misma casa, o un adulto mayor independiente) |
| BR-041 | Residencia | Cada `FamilyGroup` tiene su propio `household_admin` que gestiona únicamente sus residentes dependientes. No puede editar ni ver los residentes de otro `FamilyGroup` dentro del mismo `HouseholdUnit` |
| BR-042 | Residencia | Un `household_admin` puede visualizar qué otros `FamilyGroup` existen en su mismo `HouseholdUnit`, pero solo en modo lectura, para tener contexto de quiénes conviven en el domicilio |
| BR-043 | Onboarding | Cuando el admin aprueba un onboarding en una dirección ya existente, vincula al solicitante al `HouseholdUnit` existente creando un nuevo `FamilyGroup` dentro de él. Si la dirección es nueva, crea tanto el `HouseholdUnit` como el `FamilyGroup` |
| BR-056 | Integridad | `FamilyGroup` representa un núcleo familiar dentro de un `HouseholdUnit`. `HouseholdUnit` conserva su rol como dirección física. `FamilyGroup` pertenece a `HouseholdUnit` y contiene al `household_admin` y sus residentes dependientes. IMPLEMENTADO (verificado 2026-07-25): `app/models/family_group.rb`, tabla `family_groups` en el schema, y se crea automáticamente en `Admin::OnboardingReviewsController#approve_step3` |
| BR-044 | Identidad | Cada junta verifica los documentos de identidad de forma independiente, siempre. Que un RUN ya exista verificado en otra junta es solo informativo para el admin, no exime de la verificación |
| BR-045 | Identidad | El sistema no controla la vigencia de los documentos de identidad. Un `Member` activo opera con normalidad aunque su carnet haya vencido. La vigencia documental queda a criterio del admin de la junta |
| BR-046 | Identidad | Para corregir un RUN erróneo en una `VerifiedIdentity` aprobada: el admin desactiva al socio (BR-036) y el socio realiza un nuevo onboarding con el RUN correcto. No existe edición directa del RUN post-aprobación. Enforcement agregado 2026-07-31: `Admin::MembersController#update` permitía `:run` en los params y lo escribía directo sobre la `VerifiedIdentity` (`create` sí lo excluía) — un admin podía reescribir la identidad de un socio, y la de sus certificados ya emitidos, sin ninguna verificación documental. Ahora el controller descarta el parámetro (`.except(:run)`) y el formulario muestra el campo deshabilitado en edición |
| BR-047 | Onboarding | Una solicitud rechazada permanece en el historial del usuario con el motivo de rechazo visible. No se destruye ni archiva |
| BR-048 | Onboarding | El usuario puede iniciar una nueva solicitud de onboarding tras un rechazo. Tiene la opción de "duplicar" la solicitud rechazada para pre-cargar todos sus datos y solo corregir lo necesario, sin empezar desde cero |
| BR-049 | Onboarding | Al duplicar una solicitud rechazada, se crea una nueva `OnboardingRequest` en estado `draft` con los datos copiados. La solicitud original rechazada permanece intacta en el historial |
| BR-050 | Onboarding | El sistema envía un recordatorio-resumen diario por email a cada admin de la junta mientras tenga solicitudes en estado `pending` sin revisar. Un solo correo por admin agrupa todas las pendientes de su junta (sin spam por solicitud). Implementado vía `OnboardingRemindersJob` (recurrente en `config/recurring.yml`, `every day at 8am`) + `OnboardingReminderMailer#pending_digest` |
| BR-051 | Onboarding | El usuario puede cancelar su solicitud en estado `pending` en cualquier momento desde su panel, quedando libre para iniciar una nueva solicitud o duplicar la cancelada |
| BR-052 | Acceso | Una junta de vecinos puede tener múltiples usuarios admin simultáneos. Cualquiera de ellos puede revisar y gestionar todas las solicitudes pendientes de la junta |
| BR-053 | Acceso | Al dar de baja a un admin, las solicitudes pendientes permanecen intactas y disponibles para los demás admins de la junta. El superadmin puede asignar nuevos admins en cualquier momento |
| BR-054 | Multi-tenant | Cuando una junta se disuelve, el superadmin la marca como `inactive` (columna `active` en `neighborhood_associations`). Todos sus `Member` activos pasan a `inactive` en cascada. Implementado (2026-07-26) vía `NeighborhoodAssociation#deactivate!` + `Superadmin::NeighborhoodAssociationsController#confirm_deactivate`; no existe `destroy` (BR-100) y las cascadas de historial son `dependent: :restrict_with_error`. Enforcement agregado 2026-08-02: `AdministrationApprovalService` levanta `InactiveAssociationError` si la junta destino está disuelta. El formulario del panel ya solo ofrece juntas activas, pero el id viaja por params y la junta puede disolverse entre el envío y la revisión del staff |
| BR-055 | Multi-tenant | La disolución de una junta no migra socios automáticamente. Cada socio decide individualmente si hace onboarding en otra junta. El historial de certificados e identidad se conserva (nada se destruye — BR-100) |
| BR-057 | Identidad | Un RUN ya verificado puede aparecer en un nuevo onboarding con una cuenta de usuario distinta (ej: el residente perdió acceso a su cuenta anterior). El sistema lo permite y alerta al admin durante la revisión |
| BR-058 | Identidad | Mientras el nuevo onboarding con un RUN duplicado no sea aprobado, la membresía anterior asociada a ese RUN permanece activa e intacta. El admin es el único que puede validar si se trata de la misma persona legítima |
| BR-059 | Identidad | Solo cuando el admin aprueba el onboarding con un RUN duplicado, el `Member` anterior asociado a ese RUN pasa a estado `inactive`. La aprobación es el acto que transfiere la identidad verificada a la nueva cuenta |
| BR-060 | Identidad | Si el admin rechaza un onboarding con RUN duplicado, la membresía anterior continúa activa sin ningún cambio. El admin debe registrar el motivo del rechazo, especialmente si detecta un intento de fraude |
| BR-061 | Certificados | Un socio verificado puede solicitar tantos certificados como desee, sin restricciones por cantidad ni por estados de solicitudes previas. Certificados en `pending_payment` o pagados sin usar son responsabilidad del usuario |
| BR-062 | Certificados | Una vez que el admin aprobó el onboarding del socio (identidad + domicilio verificados), los certificados se emiten automáticamente tras el pago confirmado. No requieren revisión ni aprobación del admin por cada solicitud |
| BR-063 | Certificados | No existe posibilidad de rechazo de un certificado post-verificación. Por lo tanto no hay devoluciones de pago. El pago es el último paso antes de la emisión automática |
| BR-064 | Certificados | Los estados del certificado se simplifican a: `pending_payment` → `paid` → `issued`. Los estados `approved` y `rejected` quedan eliminados del flujo de certificados |
| BR-065 | Residencia | El `household_admin` puede registrar residentes dependientes en su `FamilyGroup` sin que estos tengan cuenta de usuario. Un **residente dependiente** es cualquier persona que no realiza el onboarding por sí misma porque no tiene la capacidad de hacerlo (adultos mayores, personas con discapacidad o deterioro cognitivo, menores de edad, etc.) — la condición es funcional, no etaria. Se modela como `IdentityVerificationRequest(dependent: true)` con `family_group_id`, `requested_by_id` y `neighborhood_association_id`. Redacción ampliada 2026-07-25 (antes decía "menores de edad", demasiado estrecho) |
| BR-066 | Identidad | El admin de la junta debe verificar la identidad del dependiente con documentación antes de aprobarlo, igual que en el onboarding estándar. Las solicitudes dependientes aparecen en `admin/dependent_reviews`, separadas del flujo normal de onboarding |
| BR-067 | Residencia | Al aprobar un dependiente, en una sola transacción se crea `VerifiedIdentity` + `Member(dependent: true, status: approved)` + `Residency(household_admin: false, status: approved)` heredando la `VerifiedResidence` del `HouseholdUnit` del `FamilyGroup` del padre |
| BR-068 | Identidad | El teléfono es opcional para dependientes (un dependiente puede no tenerlo). Las demás validaciones (RUN normalizado y dígito verificador, nombre y apellido) aplican igual que para identidades independientes |
| BR-069 | Identidad | Cuando un dependiente crece y hace su propio onboarding en cualquier junta, el mecanismo existente de RUN duplicado (BR-057-059) detecta la coincidencia. Al aprobar el nuevo onboarding, el `Member(dependent: true)` anterior pasa a `inactive` automáticamente — la graduación no requiere lógica nueva |
| BR-070 | Precios | Cada junta puede definir múltiples precios históricos con vigencia (`effective_from`, `effective_to`). El precio efectivo de un certificado es el vigente al momento de crear el `ResidenceCertificate` y queda capturado en `amount` (snapshot inmutable). Crear un nuevo precio cierra automáticamente la vigencia del anterior |
| BR-071 | Pagos | El webhook de MercadoPago es idempotente: si llega dos veces con el mismo `payment_id`, no se procesa dos veces ni se actualiza el certificado. Implementado vía índice único en `residence_certificates.payment_id` + chequeo explícito en el controller |
| BR-072 | Pagos | El webhook de MercadoPago valida la firma `x-signature` (HMAC-SHA256 con `webhook_secret`, manifest `id:{data_id};request-id:{x-request-id};ts:{ts};`) antes de procesar. **Cuando el `webhook_secret` está configurado (producción), la firma es OBLIGATORIA**: toda notificación sin `x-signature` o con firma inválida se descarta con `401 Unauthorized` (#106). La doc oficial de MP confirma que, con la clave secreta configurada, MP **siempre** firma las notificaciones Webhook (payment, merchant_order, suscripciones; única excepción: Código QR, que no usamos) — por eso la premisa previa "el feed v2.0 no manda firma" era incorrecta. Si NO hay `webhook_secret` configurado (dev/test sin secret), no se puede validar y se procesa apoyándose en la re-consulta a la API de MP. **Precondición operacional de deploy: `MERCADOPAGO_WEBHOOK_SECRET` DEBE estar configurado en producción; sin él, con este cambio se rechazarían todos los webhooks** |
| BR-073 | Pagos | Si el pago es rechazado, refunded o cancelado por MP, el certificado vuelve/permanece en `pending_payment`. El usuario puede reintentar pagando desde la UI (BR-003). El webhook no degrada un certificado ya `issued` |
| BR-074 | Certificados | El `validation_token` (UUID) y `validation_code` (alfanumérico de 8 caracteres, sin 0/O/1/I para evitar confusión visual) se generan al emitir el certificado y son únicos en la base de datos. El código se usa para verificación manual/telefónica; el token para el QR |
| BR-075 | Certificados | El PDF se genera una sola vez al emitir y se almacena vía Active Storage (`pdf_document`). Descargas posteriores reutilizan el archivo almacenado |
| BR-076 | Certificados | La transición `paid → issued` se ejecuta en un job asíncrono (`IssueCertificateJob`) disparado tras confirmar el pago vía `after_commit`. Si la generación del PDF falla, el job reintenta hasta 3 veces con backoff polinomial; si todos fallan, el certificado queda en `paid` para revisión manual |
| BR-077 | Certificados | Eliminada la acción manual `Admin::ResidenceCertificatesController#issue`. La emisión es exclusivamente automática (BR-062). El admin ya no puede forzar emisión sin pago. La columna `residence_certificates.approved_by_id` (y su asociación, la fila de la vista admin y `User#approved_certificates`) fue eliminada el 2026-08-02: nunca se asignaba en ningún flujo y sugería una semántica de aprobador inexistente |
| BR-078 | Validación | El RUN del titular se muestra parcialmente oculto en la verificación pública (formato `1.XXX.XXX-K`) para proteger privacidad. La verificación pública no expone datos completos del titular |
| BR-079 | Validación | El endpoint `/verify/:identifier` acepta el `validation_token` (UUID) o el `validation_code` (8 chars alfanumérico, case-insensitive). Ambos resuelven al mismo certificado vía `ResidenceCertificate.find_for_public_verification` |
| BR-080 | Validación | Un certificado con `expiration_date < today` se muestra como **Vencido** con response 200 OK (cumple BR-009 — URL responde indefinidamente). Solo identificadores **inexistentes** o certificados no-`issued` retornan 404 |
| BR-081 | Validación | La verificación pública nunca expone certificados que no estén en estado `issued`. El scope `findable_publicly` filtra automáticamente; el controller no puede ser engañado vía URL para mostrar certs en `pending_payment` o `paid` |
| BR-082 | Residencia | El registro de convivientes del domicilio se realiza exclusivamente vía el flujo de residentes dependientes (BR-065 a BR-069). El antiguo flujo "Socios del Domicilio" (`panel/members`) fue eliminado en 2026-07-22: estaba incompleto (creaba `Residency` en `pending` sin revisión admin posible y sin `Member`, rompiendo BR-027 al solicitar certificados) y duplicaba la funcionalidad de dependientes |
| BR-083 | Pagos | Para habilitar una publicación del marketplace el usuario debe pagar vía MercadoPago (mismo mecanismo Checkout Pro que los certificados). Estados de publicación: `pending_payment` → `published`. Solo el webhook con pago `approved` publica; pagos rechazados/pendientes no cambian el estado |
| BR-084 | Precios | Cada junta define el precio de habilitación de publicaciones con vigencias históricas (`ListingPricing`, espejo de BR-070). Mínimo $1.000 CLP. El monto se captura en `amount` (snapshot) al iniciar el pago. Para pagar, el usuario debe ser socio activo de una junta y esa junta debe tener precio vigente |
| BR-085 | Comisión | Yuntapp retiene el 10% del pago de cada publicación (`platform_fee`); el 90% es para la junta del socio, registrada como snapshot en `listings.neighborhood_association_id` |
| BR-086 | Pagos | La publicación queda vigente 30 días desde el pago (`published_until`). Al vencer puede renovarse con un nuevo pago, que otorga 30 días desde el nuevo pago. Las publicaciones existentes antes del cobro recibieron 30 días de gracia en la migración |
| BR-087 | Pagos | El webhook de MercadoPago es compartido entre certificados y publicaciones: `external_reference` con prefijo `listing-<id>` enruta a `Listing`; un id a secas enruta a `ResidenceCertificate` (formato original). La idempotencia **histórica** vive en la tabla `payment_events` con clave `(payment_id, status)` (#101): cada evento de pago procesado (approved/refunded/charged_back/…) se registra con referencia polimórfica al payable. El gate del flujo de **suscripción** (`process_subscription_authorized_payment`) consulta `payment_events` por `(payment_id, "approved")` — antes usaba el campo `payment_id` del `Listing`, que `renew_from_subscription!` sobrescribía en cada cobro, perdiendo el historial y permitiendo re-renovar ante reintentos tardíos. El flujo de **pago único** conserva su idempotencia por estado (`payment_status`, Batch G/BR-141) y solo registra eventos como log histórico. La clave incluye `status` para no bloquear un refund/contracargo posterior del mismo pago |
| BR-088 | Pagos | Las publicaciones pueden auto-renovarse vía Suscripciones de MercadoPago (`preapproval`, frecuencia mensual), opcional al pago único. El monto queda fijo al autorizar (snapshot del precio vigente); si la junta cambia su precio, las suscripciones vigentes mantienen el monto antiguo — para tomar el nuevo, el usuario debe cancelar y volver a suscribirse. El usuario puede cancelar en cualquier momento desde su panel. Enforcement agregado 2026-08-02: cancelar es idempotente desde la perspectiva del usuario — si MP ya dejó la preapproval en un estado terminal (el usuario la canceló en la app de MP, o MP la dio de baja tras cobros fallidos), el error del SDK se registra y el estado local se marca `cancelled` igual. Antes propagaba un 500 y dejaba la suscripción local intacta, sin salida |
| BR-089 | Pagos | Cada cobro recurrente aprobado (webhook `subscription_authorized_payment`) extiende la vigencia 30 días desde el vencimiento vigente si la publicación está al día, o desde la fecha del cobro si estaba vencida. Cancelar la suscripción no corta la vigencia ya pagada: la publicación vence normalmente. Si el cobro recurrente falla, la publicación simplemente vence (BR-086) sin degradarse antes |
| BR-090 | Pagos | El webhook valida que `transaction_amount` del pago coincida exactamente con el `amount` del certificado o publicación antes de marcar como pagado. Pagos con monto distinto o sin monto se descartan con log de advertencia (protege contra manipulación y contra pagos obsoletos con `external_reference` coincidente). Demostrado en sandbox 2026-07-22: un pago antiguo de $2.000 marcó como pagado un certificado de $1.500 |
| BR-091 | Certificados | La desactivación de un socio (BR-036) bloquea sus certificados: no puede solicitar nuevos (se exige `Member` aprobado en la junta, no basta la `Residency` aprobada) ni descargar los existentes, y la verificación pública muestra sus certificados como **No válido** (con precedencia sobre Vencido) mientras el `Member` esté `inactive`. Implementado vía `holder_deactivated?`/`downloadable?` en el modelo y `ensure_active_member!` en el panel. Enforcement extendido 2026-08-02 a `Panel::DependentsController`: `household_admin?` se apoya en la `Residency`, que por BR-038 no cambia al desactivar el `Member`, así que seguía devolviendo `true` y el socio dado de baja podía registrar dependientes — al aprobarlos el admin se le recreaba un `Member(approved)`, deshaciendo su propia desactivación |
| BR-092 | Certificados | Los certificados vencidos no pueden descargarse desde el panel — aplica a todos los socios, activos o no. Si el socio necesita el documento, solicita uno nuevo. La verificación pública sigue mostrándolos como Vencido con 200 OK (BR-009/BR-080 intactos). La descarga pasa por `panel/residence_certificates/:id/download`, que valida `downloadable?` antes de servir el PDF |
| BR-093 | Acceso | El email de la cuenta de usuario es inmutable después del registro. La vista "Mi Cuenta" (`users/registrations/edit`) lo muestra deshabilitado y `Users::RegistrationsController` descarta el parámetro `email` en el update (defensa server-side ante formularios manipulados). Quien necesite otro correo debe registrar una cuenta nueva; la identidad verificada se traslada mediante el mecanismo de RUN duplicado (BR-057–BR-059) |
| BR-094 | Acceso | El cambio de contraseña se realiza exclusivamente en "Mi Cuenta" (Devise registrations), que exige la contraseña actual. "Mi Perfil" (`panel/profile`) es solo consulta: no tiene acción `update` (eliminada 2026-07-23 — permitía cambiar la contraseña sin la contraseña actual y aceptaba `email` en los params, contradiciendo BR-093) |
| BR-095 | Residencia | Un `household_admin` activo puede transicionar a **residente dependiente** de otro `FamilyGroup` (ej: un adulto mayor autónomo que pierde capacidad y pasa a depender de un familiar). Al registrarlo como dependiente por su RUN (detección de RUN duplicado, BR-057–059), su `Member(household_admin)` anterior pasa a `inactive` y su cuenta de usuario pierde acceso operativo (no puede seguir operando como admin de domicilio). La identidad no se destruye: queda como historial auditable (BR-030) |
| BR-096 | Residencia | Al transicionar un `household_admin` a dependiente, sus propios residentes dependientes quedan desvinculados y sus `Member(dependent: true)` pasan a `inactive` en cascada (consistente con BR-034/BR-037). Esas identidades quedan como historial: para volver a estar activas, cada una debe partir de nuevo — mediante un onboarding propio completo (BR-035) o siendo registradas de nuevo como dependientes por el `household_admin` que asuma el `FamilyGroup` |
| BR-097 | Certificados | Al transicionar un `household_admin` a dependiente (BR-095), sus certificados emitidos quedan invalidados: al pasar su `Member` a `inactive` operan bajo BR-091 (verificación pública "No válido" con precedencia sobre Vencido, y descarga bloqueada). No existe revocación individual de certificados (BR-008/BR-064); la invalidación es efecto automático de la desactivación del titular. Lo mismo aplica a los certificados de sus dependientes desvinculados (BR-096) |
| BR-098 | Certificados | El `household_admin` puede solicitar certificados **a nombre de** cualquier residente dependiente de su domicilio; el titular del certificado es el `Member(dependent: true)` del residente, no el admin. Esto matiza BR-022/BR-033: el dependiente nunca opera ni inicia sesión, pero sí puede ser titular de un certificado gestionado por el admin (crítico para dependientes adultos —mayores, personas con discapacidad— que requieren su propio certificado de residencia). Implementado en `Panel::ResidenceCertificatesController`: `selectable_residencies` ofrece todo residente del `household_unit` con `Member` aprobado en la junta, y `create` fija ese `Member` como titular. El dependiente debe tener `Member` aprobado y activo — dependientes desactivados (BR-037) quedan excluidos del selector |
| BR-099 | Integridad | **Regla general de cascada**: siempre que el `Member` de un `household_admin` pasa a `inactive` —por cualquier causa: unirse a otra junta (BR-029), cambio de dirección (BR-031), reinicio de onboarding (BR-018), desactivación manual del admin (BR-036) o transición a dependiente (BR-095)— sus residentes dependientes quedan desvinculados y sus `Member(dependent: true)` pasan a `inactive` en cascada automáticamente. Se asume que los dependientes acompañan al `household_admin`. Esas identidades quedan como historial auditable (BR-030); para volver a estar activas, cada dependiente debe partir de nuevo con su propio onboarding completo (BR-035/BR-069) o ser registrado otra vez como dependiente por quien asuma el `FamilyGroup`. Esta regla generaliza BR-034/BR-037/BR-096, que son casos particulares del mismo invariante |
| BR-101 | Acceso | **Las cuentas de usuario no se borran; se desactivan o bloquean.** (a) **Auto-desactivación** (`deactivated_at`): el usuario da de baja su cuenta desde el panel; bloquea el login y cascadea sin borrar (Members activos → `inactive`, onboarding pendientes → `cancelled`, listings despublicadas). Es reversible **por el propio usuario vía su correo**: `ReactivationsController` + `ReactivationMailer` con `generates_token_for(:account_reactivation)` (válido 24h, se invalida al reactivar). El `User` no tiene RUN — la identidad/RUN vive en `VerifiedIdentity`; la reactivación es por email. (b) **Bloqueo** (`blocked_at`/`blocked_by`/`block_reason`): lo aplica un superadmin; bloquea el login y **el usuario no puede auto-reactivarse** (solo `unblock!` de un superadmin). Un superadmin **no es bloqueable** (reservado para el futuro split superadmin real / staff). Enforcement: `User#active_for_authentication?` (Devise) + guard `before_destroy` en `User` (bloquea incluso el `destroy` de Devise registrations) + sin acciones `destroy` en `admin/users`/`superadmin/users`. El flujo dev-only `account_reset` fue eliminado (2026-07-27) |
| BR-100 | Integridad | **Ningún dato consolidado se destruye.** La información generada en la plataforma (identidades verificadas, socios, residencias, certificados emitidos, directiva, publicaciones) debe sobrevivir a errores, cambios y "borrados". Un `Member`, una vez creado, **nunca** se destruye: solo se desactiva (`deactivate!` → `inactive`), conservando su historial. Enforcement: guard `before_destroy` en `Member` que aborta la destrucción por cualquier ruta; `residence_certificates`/`board_members` con `dependent: :restrict_with_error` (no `:destroy`); sin acción `destroy` en `admin/members`; y el restablecimiento de cuenta (`panel/account_resets`) desactiva y desvincula en vez de destruir. Los borrados físicos que aún existan (p. ej. cascadas `dependent: :destroy` en `NeighborhoodAssociation` — issue #90) deben migrarse a este modelo |
| BR-119 | Integridad | RUT de la organización **obligatorio**, normalizado + DV módulo 11, **único** entre juntas, almacenado en `NeighborhoodAssociation`. Es la prueba de constitución legal de la junta |
| BR-120 | Certificados | La emisión de certificados (BR-062) y el cobro de publicaciones exigen junta con RUT válido. Una junta no constituida legalmente no puede emitir — hacerlo violaría la ley chilena |
| BR-121 | Integridad | **No puede existir `NeighborhoodAssociation` sin RUT** (columna `NOT NULL`, único, DV válido módulo 11). El RUT **no codifica semántica de entorno**: un RUT en cualquier rango —incluido 70.000.000–99.999.999— puede pertenecer a una organización o persona real, en producción o desarrollo. Las juntas heredadas se regularizan asignándoles un RUT válido; para las juntas demo existentes se usan los 10 RUTs provistos (que son solo RUTs válidos, no un marcador de prueba). Distinguir juntas demo, si se necesita, requiere un marcador explícito aparte del RUT |
| BR-122 | Acceso | Solo el staff (superadmin) aprueba/rechaza una solicitud de administración. Ningún admin de junta ni otro rol puede |
| BR-123 | Administración | El solicitante declara su cargo (presidente/secretario/tesorero/director) y adjunta **obligatoriamente** el certificado de vigencia de la directiva y el RUT de la organización. Sin ambos no pasa a `pending`. Enforced: validación `directiva_validity_document_attached` (on `pending`) en `AdministrationRequest` + RUT vía `run:` validator |
| BR-124 | Administración | Precondición: cuenta con email confirmado. Flujo institucional, no auto-registro abierto |
| BR-125 | Administración | Apunta a junta del catálogo (región→comuna→junta) o propone una nueva (nombre + comuna). La junta nueva **no se crea hasta aprobar**; antes no es visible ni seleccionable por residentes |
| BR-126 | Administración | Estados: `draft` → `pending` → `approved`/`rejected`; `cancelled` disponible en `pending` (espejo de `OnboardingRequest`) |
| BR-127 | Identidad | Datos del dirigente con las mismas normalizaciones/validaciones del residente: RUN+DV (BR-010/011), teléfono +569 (BR-013), nombres capitalizados (BR-014) |
| BR-128 | Integridad | Aprobación transaccional: crea/enlaza `NeighborhoodAssociation` (con RUT); **reutiliza** `VerifiedIdentity` por RUN si existe (ADR-006 si es de otra cuenta) o la crea; **reutiliza** el `Member` de esa junta si existe, si no crea `Member(approved)`; crea `BoardMember(cargo, start_date hoy, active)`; marca `User` admin + FK. Todo o nada |
| BR-129 | Identidad | Si el RUN pertenece a otra cuenta, aplica transferencia de identidad por RUN duplicado (BR-057–059 / ADR-006). El staff debe **confirmar explícitamente** la transferencia al aprobar (checkbox obligatorio + guarda `confirm_duplicate_run` en `Superadmin::AdministrationRequestsController#approve`) cuando el RUN ya está verificado en una identidad distinta a la del solicitante |
| BR-130 | Administración | Junta con admin activo: los admins vigentes son notificados y pueden objetar; el staff decide. La aprobación **agrega co-admin** (BR-052), no reemplaza |
| BR-131 | Administración | Rechazo con motivo obligatorio; queda en historial; el usuario puede duplicar/re-enviar (espejo BR-047–049) |
| BR-132 | Multi-tenant | El admin solo ve/gestiona su junta (BR-007). Su `Member` se crea sin `Residency`/`HouseholdUnit`: no habilita certificados a su nombre hasta hacer onboarding de residencia |
| BR-133 | Administración | Digest diario al staff de solicitudes pendientes (espejo BR-050); el solicitante es notificado en cada transición |
| BR-134 | Administración | Un usuario tiene a lo más **una** solicitud de administración activa (`draft`/`pending`) a la vez |
| BR-135 | Precios | Junta nueva arranca sin `CertificatePricing`/`ListingPricing`; el admin debe definir precio (mín. $1.000 — BR-005/070/084) antes de operar |
| BR-136 | Acceso | Un usuario solo puede administrar **una** junta a la vez (FK único `User.neighborhood_association_id`). Si ya es admin, no puede solicitar otra administración hasta dejar la actual |
| BR-137 | Integridad | **Consecuencia del acoplamiento admin↔socio**: si el dirigente ya era socio activo de **otra** junta, aprobarlo desactiva su `Member` anterior (BR-029) → invalida sus certificados de esa junta (BR-091) y, si era `household_admin`, desactiva en cascada a sus dependientes (BR-099). Si ya era socio de la **misma** junta, se reutiliza sin desactivar nada. El sistema **advierte** al solicitante y al staff de esta consecuencia antes de aprobar. Advertencias implementadas 2026-08-02: `memberships_to_deactivate` en la vista del staff y el aviso al solicitante en el formulario del panel. La cascada ya se ejecutaba; lo que faltaba era avisar antes |
| BR-138 | Administración | El acceso de admin **no caduca** automáticamente al vencer el período de la directiva (`end_date`). La vigencia queda a criterio del staff/junta (espejo BR-045); la revocación es manual |
| BR-139 | Administración | Junta nueva con nombre+comuna igual a una existente → **advertencia** de posible duplicado al staff (no bloqueo duro); decide el staff. Implementada 2026-08-02 vía `possible_duplicate_association` en la show del staff |
| BR-140 | Administración | Cargo de directiva ya ocupado por un `BoardMember` activo → **advertencia** al staff; no se desplaza automáticamente al titular vigente. Implementada 2026-08-02 vía `position_already_taken_by` en la show del staff |
| BR-141 | Certificados | Un pago revertido por MercadoPago (`refunded`/`charged_back`, típicamente un contracargo iniciado por el banco del comprador días/semanas después) invalida el certificado. Se registra en `payment_status` (columna cruda de MP, no cambia el enum `status`/BR-064). Si el certificado ya fue **emitido**: sigue `issued` (inmutable, BR-008) pero la verificación pública lo muestra **No válido** (precedencia sobre Vencido, junto con BR-091 — `payment_reverted?`) y la descarga desde el panel queda bloqueada (`downloadable?`); el PDF ya descargado queda fuera de alcance pero sin valor de verificación. Si aún estaba **`paid`** (no emitido): vuelve a `pending_payment` (BR-073). Si es una **publicación** `published`: se despublica. Es la **primera vía de invalidación individual** de un certificado (matiza BR-008/BR-064/BR-097). El staff (superadmin) es notificado (`PaymentReversalMailer`) para evaluar fraude y, si corresponde, desactivar al socio (BR-091). Implementado vía `ResidenceCertificate#apply_mp_payment_status!` + webhook idempotente por estado. Endurecido 2026-08-02: `mark_as_paid!`, `apply_mp_payment_status!` e `issue!` corren dentro de `with_lock`, que recarga el registro antes de decidir. Sin eso, un job que había cargado el certificado como `paid` seguía emitiéndolo aunque un webhook de contracargo ya lo hubiera devuelto a `pending_payment` |
| BR-142 | Pagos | La renovación automática de una publicación (suscripción MP, BR-088) exige un paso previo donde el usuario **confirma el correo de su cuenta MercadoPago** (`payer_email`). MP rechaza el cobro recurrente si el `payer_email` de la preapproval no coincide con el correo real del pagador, y el correo de la cuenta yuntapp es inmutable (BR-093), por lo que puede no ser el mismo. El correo confirmado se persiste en `users.mercadopago_email` (validado como email, `allow_blank`) para pre-cargarlo en futuras suscripciones. Flujo: `Panel::ListingSubscriptionsController#new` muestra el formulario pre-cargado con `mercadopago_email` o, si está vacío, el correo de login; `#create` valida el email, lo guarda, captura el precio (snapshot, BR-084) y crea la preapproval con ese `payer_email`. No altera BR-093 (`mercadopago_email` es un campo aparte, no el login) |
| BR-143 | Pagos | **La vitrina pública solo muestra publicaciones habilitadas.** `ListingsController` (index/show/search y el bypass `items=all`) consulta exclusivamente el scope `Listing.published` = `publication_status: published` + `published_until >= hoy` + no retirada. Formaliza el enforcement de BR-083/BR-086: como toda publicación nace en `pending_payment`, el `Listing.all` anterior permitía **publicar gratis** (y dejaba visibles las vencidas). `show` de una publicación no habilitada responde 404. Detectado en la auditoría profunda 2026-07-30 |
| BR-144 | Integridad | **Una publicación con historial de pago no se destruye: se retira.** Extensión de BR-100 al marketplace — el registro conserva su snapshot financiero (`amount`, `platform_fee`, junta beneficiaria BR-085) aunque su dueño la "elimine". `Listing#ever_paid?` (payment_id, paid_at, published_until o payment_events) discrimina: si nunca se pagó es un borrador y sí se destruye; si se pagó, `withdraw!` la marca `active: false` y sale de la vitrina (BR-143) sin tocar la vigencia comprada. Enforcement: guard `before_destroy` en `Listing` + ramas en `Panel::ListingsController#destroy` y `Admin::ListingsController#destroy`. `active` pasa a significar "visible en la vitrina" (NULL = visible, por las publicaciones anteriores a esta regla) |
| BR-145 | Pagos | **El monto de la suscripción vive en `listings.subscription_amount`, no en `amount`.** BR-088 fija el monto al autorizar la preapproval, pero `amount` se reescribe con el precio vigente cada vez que el usuario abre pagar/suscribirse: si la junta subía su precio, el cobro recurrente legítimo de MP (por el monto pactado) dejaba de coincidir con `amount` y el gate de BR-090 lo rechazaba — **el usuario pagaba y su publicación vencía igual**. El webhook de cobro recurrente valida contra `subscription_amount` (snapshot inmutable capturado en `ListingSubscriptionsController#create`), con fallback a `amount` para las suscripciones anteriores al backfill |
| BR-146 | Pagos | **Una reversión es definitiva para ese `payment_id`.** Si existe un `PaymentEvent(payment_id, refunded\|charged_back)`, toda notificación posterior que traiga ese mismo pago como `approved` se descarta (log de advertencia, 200 OK). Cierra la vía por la que un `merchant_order` tardío —que reprocesa sus payments anidados— o una consulta a la API de MP con estado obsoleto podía deshacer la invalidación de BR-141 y volver a marcar pagado un certificado con contracargo. La guarda es **por pago, no por recurso**: si el usuario vuelve a pagar tras la reversión, ese pago nuevo trae otro `payment_id` y se procesa normal (BR-003/BR-073) |
| BR-147 | Certificados | **El PDF del certificado se sirve autorizado en cada descarga.** `Panel::ResidenceCertificatesController#download` responde con `send_data` en vez de redirigir a `rails_blob_path`: la URL de Active Storage depende solo del `signed_id` —no de `current_user` ni de `downloadable?`— y con el servicio Disk no expiraba, así que quien guardara esa URL seguía descargando el certificado después de ser desactivado (BR-091), de que venciera (BR-092) o de que le revirtieran el pago (BR-141). Complemento: `config.active_storage.urls_expire_in = 5.minutes` acota las URLs de los documentos de identidad que sí se enlazan desde las vistas de admin/staff |
| BR-148 | Certificados | **No se puede solicitar ni pagar un certificado si la junta no tiene RUT válido**, y una emisión que agota sus reintentos avisa al staff. Precondición de BR-120: `issue!` ya abortaba sin RUT, pero nada impedía crear la solicitud ni cobrarla, así que el certificado quedaba `paid` para siempre — sin emisión, sin devolución (BR-063) y sin que nadie se enterara. Enforcement: `ensure_association_constituted!` en `Panel::ResidenceCertificatesController#new/create` y en `Panel::PaymentsController#new`; `IssueCertificateJob` notifica a todos los superadmin (`CertificateIssuanceFailureMailer`) cuando `retry_on` se rinde, cualquiera sea la causa. **Alcance real**: desde BR-121 la columna `rut` es `NOT NULL` con validación de presencia, así que una junta sin RUT no es alcanzable por la aplicación — los guards son defensa en profundidad; el aviso al staff es lo que cubre fallos de emisión reales (PDF, folio, datos corruptos) |
| BR-149 | Comisión | **`platform_fee` refleja siempre el 10% del monto realmente cobrado.** `compute_platform_fee` solo corre cuando el fee está `nil`, y en las publicaciones `amount` se reescribe con el precio vigente cada vez que el usuario abre "pagar", mientras MP sigue cobrando el `subscription_amount` pactado (BR-145). Sin re-sincronizar, una junta que subía su precio dejaba la publicación renovada registrando una comisión sobre un monto que nadie pagó. Enforcement: `Listing#renew_from_subscription!` re-captura `amount = charged_subscription_amount` y fuerza el recálculo del fee, con una excepción explícita en `pricing_snapshot_immutable_while_published` (no es re-captura del precio de la junta, es el registro del dinero del ciclo). En `ResidenceCertificate` no aplica: su `amount` se fija al crear y ninguna ruta lo reescribe |

### Categorías disponibles
- **Acceso**: quién puede hacer qué y condiciones de autorización
- **Pagos**: flujo y estados del pago con MercadoPago
- **Comisión**: reglas de la tarifa de Yuntapp
- **Precios**: restricciones de precio para las juntas
- **Integridad**: invariantes del modelo de datos y transacciones
- **Multi-tenant**: aislamiento entre asociaciones vecinales
- **Validación**: comportamiento del sistema de verificación de certificados
- **Normalización**: transformaciones automáticas de datos de entrada
- **Identidad**: reglas sobre `VerifiedIdentity` y el RUN chileno
- **Residencia**: reglas sobre domicilios y `HouseholdUnit`
- **Onboarding**: reglas del flujo de solicitud de membresía
- **Certificados**: reglas sobre `ResidenceCertificate` y su ciclo de vida
- **Administración**: onboarding de administradores/dirigentes y creación/administración de juntas

---

## Stack Tecnologico

> Versiones verificadas contra `.ruby-version` y `Gemfile.lock` el 2026-08-18. Actualizar esta tabla al subir dependencias mayores.

| Componente | Version | Nota |
|---|---|---|
| Ruby | 4.0.6 | Fijada en `.ruby-version` |
| Rails | 8.1.3.1 | |
| Bundler | 2.6.9 | `BUNDLED WITH` en `Gemfile.lock` |
| SQLite3 | 2.9.6 | Base de datos en `storage/` |
| Devise | 5.0.4 | Autenticacion |
| Pagy | 43.6.1 | Paginacion |
| Propshaft | 1.3.2 | Asset pipeline |
| Importmap Rails | 2.2.3 | Sin bundler JS (no hay `package.json`) |
| Tailwind CSS Rails | 4.6.0 | Tailwind v4 |
| DaisyUI | plugin local | `app/assets/tailwind/daisyui.mjs` |
| Solid Queue | 1.6.0 | Background jobs |
| Solid Cache | 1.0.10 | Cache |
| Solid Cable | 4.0.2 | WebSockets |
| Kamal | 2.12.0 | Deploy con Docker |
| Thruster | 0.1.25 | Aceleracion HTTP |
| Minitest | 6.0.6 | Tests con fixtures YAML |
| SimpleCov | 1.1.1 | Cobertura |
| Standard | 1.56.0 | Linting Ruby — linter unico (ADR-0011) |
| standard-rails | 1.6.0 | Plugin de Standard: cops de `rubocop-rails` 2.34.3. No es un segundo linter |
| ERB Lint | 0.9.0 | Linting de vistas |
| Brakeman | 8.0.6 | Analisis de seguridad |

**Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS v4, DaisyUI. Sin Webpack ni esbuild.

---

## Arquitectura de la Aplicacion

### Tres Niveles de Acceso

1. **Superadmin** (`user.superadmin?`): Gestiona paises, regiones, comunas, asociaciones, categorias, tags y usuarios globales. Puede impersonar asociaciones para administrarlas. Layout `superadmin`.
2. **Admin** (`user.admin?` + `neighborhood_association_id`): Administra una junta de vecinos especifica. Gestiona delegaciones, domicilios, socios, verificaciones, directiva, certificados y publicaciones. Layout `admin`.
3. **Usuario/Socio** (panel): Accede al panel de usuario. Realiza onboarding, gestiona su perfil, solicita certificados, publica en marketplace. Layout `panel`/`application`.

### Autorizacion

- `ApplicationController`: requiere `authenticate_user!` globalmente via Devise.
- `Admin::ApplicationController`: verifica `ensure_neighborhood_admin!` (superadmin o admin con asociacion).
- `Superadmin::ApplicationController`: verifica `ensure_superadmin!`.
- Despues del login, usuarios no-superadmin son redirigidos a `panel_root_path`.
- Superadmin puede impersonar asociaciones via `session[:impersonated_neighborhood_association_id]`.

### Flujo de Onboarding (4 pasos)

El onboarding es el flujo principal para que un usuario se convierta en socio:

1. **Step 1 - Seleccion de Asociacion**: Selects en cascada Region -> Comuna -> Asociacion Vecinal. Usa Turbo Streams para actualizar campos dinamicamente. Crea/actualiza `OnboardingRequest`.
2. **Step 2 - Verificacion de Identidad**: Captura nombre, apellido, RUN, telefono y documentos de identidad. Crea `IdentityVerificationRequest`. Validacion con autosave via Turbo Streams.
3. **Step 3 - Verificacion de Residencia**: Seleccion de delegacion vecinal o direccion manual. Crea `ResidenceVerificationRequest`. Checkbox para alternar entre select de delegacion e input de direccion.
4. **Step 4 - Revision y Envio**: Muestra resumen de todos los datos. Al enviar, cambia el status de onboarding_request a "pending".

Rutas de onboarding: `panel/onboarding/step1..4`, con PATCH para actualizaciones parciales.

## Patrones y Convenciones

### Controladores
- Todos los recursos CRUD siguen un patron consistente con acciones: index, show, new, create, edit, update + `search` (collection) y `delete` (member, vista de confirmacion).
- Filtrado dinamico: los controladores usan `filter_scope` y `sort_scope` helpers que convierten params a nombres de scope (`filter_by_{attr}`, `sort_by_{col}`).
- Paginacion con Pagy en listados.

### Vistas
- Vistas ERB con Tailwind/DaisyUI.
- Helpers: `input_class(model, field)` para clases de validacion, `error_message(invalid, messages)` para errores inline, `icon(name)` para SVG icons.
- `sort_link` helper para columnas de tabla ordenables.
- Turbo Frames y Turbo Streams para interactividad sin SPA.

### Modelos
- Todos heredan de `ApplicationRecord` que incluye Sortable y Filterable.
- Status como constantes string (no enums de Rails), con metodos `status?` manuales.
- Normalizacion de datos en callbacks `before_validation`.
- Delegacion de atributos para evitar law of demeter violations.

### Tests
- Minitest con fixtures YAML.
- Tests de modelos, controladores y system tests (Capybara + Chrome headless).
- SimpleCov para cobertura de codigo.
- Ejecutar tests: `bin/rails test`
- Ejecutar test especifico: `bin/rails test test/models/user_test.rb`
- **System tests: `bin/rails test:system`** — `bin/rails test` NO los incluye, Rails los excluye por
  defecto. Corren en `bin/ci` como paso propio, y solo en local: la imagen de produccion no trae Chrome.
- Los system tests se escriben **por caso de uso (UC-XXX), no por regla de negocio**. Cubren lo que vive
  en el cliente y ningun controller test alcanza: selects en cascada por Turbo Stream, autosave de
  Stimulus, botones que el servidor habilita. Las reglas de negocio se prueban en el nivel que les
  corresponde — modelo para invariantes y normalizacion, controller para autorizacion y multi-tenant
  (un POST manipulado no se reproduce con clicks).

## Idioma

La aplicacion esta primariamente en espanol (interfaz, mensajes flash, labels de formularios). Los archivos i18n estan en `config/locales/es.yml` y `config/locales/en.yml`. Las vistas del admin, panel y onboarding usan traducciones i18n extensivamente.

## Agent Team Configuration

> **OBLIGATORIO:** Para cualquier tarea de codigo (feature, fix, refactor, UI), seguir este workflow sin que el usuario lo pida.

### Archivos compartidos (`.claude/team/`)

```
backlog.md                 # Tareas pendientes
current-sprint.md          # Sprint actual
architecture/decisions.md  # Puntero a doc/adr/ (los ADRs se unificaron alli el 2026-08-02)
reviews/pending.md         # PRs en revision
bugs/active.md             # Bugs activos
```

Los **ADRs** viven en [`doc/adr/`](doc/adr/README.md), fuente unica. Formato y numeracion en el README de ese directorio.

### Roles

| Rol | Responsabilidad |
|-----|----------------|
| Arquitecto | Diseno, ADRs, sprint planning |
| Desarrollador | Implementacion |
| Tester | Tests |
| Reviewer | Code review |
| Documentador | Docs, CLAUDE.md |

Indicar rol al inicio: `Como [DESARROLLADOR]: Implementando...`

### Worktrees — Aislamiento por Sesion

Crear un worktree al inicio de **cada sesion de codigo**:

```
EnterWorktree(name: "{tipo}-{slug}")
```

| Tipo | Prefijo | Ejemplo |
|------|---------|---------|
| Feature | `feat-` | `feat-filtros-socios` |
| Bug fix | `fix-` | `fix-onboarding-crash` |
| Refactor | `refactor-` | `refactor-service-objects` |
| UI | `ui-` | `ui-admin-dashboard` |
| Tests | `test-` | `test-residence-certificate` |

**Flujo completo por sesion**:
```
1. EnterWorktree(name: "fix-mi-tarea")
2. Leer .claude/team/ → registrar en current-sprint.md
3. Implementar cambios
4. Actualizar reviews/pending.md con el PR
5. git add / commit / push
6. gh pr create
7. ExitWorktree(action: "keep")    # "remove" si se abandona sin cambios
```

**Reglas**:
1. Siempre `EnterWorktree` antes de escribir codigo
2. Los archivos compartidos son la fuente de verdad
3. Leer estado actual antes de actuar
4. Documentar decisiones de arquitectura como un ADR nuevo en `doc/adr/`
5. Usar IDs unicos: `BUG-XXX`, `ADR-XXX`, `#XXX`

