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
| 4 | El estado se muestra como: **Válido**, **Vencido**, o **Anulado** |

**Postcondición**: El verificador obtiene confirmación de la autenticidad del certificado sin necesidad de contactar a la junta.

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
| BR-007 | Multi-tenant | Un admin solo puede ver y gestionar datos de su propia junta. El superadmin puede ver todo |
| BR-008 | Integridad | Una vez en estado `issued`, el certificado es inmutable. Para corregir errores: rechazar y emitir uno nuevo |
| BR-009 | Validación | La URL pública de verificación debe responder indefinidamente, incluso para certificados vencidos (mostrar "vencido", no 404) |
| BR-010 | Normalización | El RUN se normaliza antes de validar: eliminar puntos y espacios, convertir a mayúsculas, insertar guión antes del dígito verificador (ej: `12.345.678-k` → `12345678-K`) |
| BR-011 | Identidad | El dígito verificador del RUN debe ser válido según el algoritmo módulo 11 chileno. Rechazar RUN con dígito incorrecto |
| BR-012 | Identidad | El RUN es único en `verified_identities`. No pueden existir dos identidades verificadas con el mismo RUN |
| BR-013 | Normalización | El teléfono se normaliza a formato `+569XXXXXXXX`. Si ingresa `9XXXXXXXX` (9 dígitos), se agrega `+56` automáticamente |
| BR-014 | Normalización | Los nombres se normalizan: primera letra de cada palabra en mayúscula, resto en minúsculas, sin espacios extras |
| BR-015 | Onboarding | El socio debe aceptar los términos (`terms_accepted_at` presente) para enviar la solicitud de onboarding |
| BR-016 | Onboarding | Al cambiar de región se resetean comarca y asociación. Al cambiar de comuna se resetea la asociación (cascada) |
| BR-017 | Onboarding | El envío de onboarding es atómico: `OnboardingRequest`, `IdentityVerificationRequest` y `ResidenceVerificationRequest` pasan a `pending` juntos o ninguno |
| BR-018 | Onboarding | Al reiniciar el onboarding se elimina el `Member` activo y se cancela la solicitud pendiente. Es una acción destructiva |
| BR-019 | Residencia | Para completar el paso de domicilio: se requiere `neighborhood_delegation_id` O `street_name`, no pueden ambos estar vacíos |
| BR-020 | Residencia | El número de vivienda (`number`) es siempre obligatorio en el domicilio |
| BR-021 | Residencia | El primer residente aprobado de un domicilio recibe `household_admin: true` en su `Residency`. Los siguientes no |
| BR-022 | Acceso | Solo el `household_admin` del domicilio puede solicitar certificados y agregar nuevos miembros al hogar |
| BR-023 | Certificados | Los certificados vencen 6 meses después de la fecha de emisión (`issue_date + 6.months`) |
| BR-024 | Integridad | La aprobación del onboarding es transaccional: crea `VerifiedIdentity`, `VerifiedResidence`, `HouseholdUnit`, `Residency` y `Member` en una sola transacción. Si algo falla, se revierte todo |
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
| BR-038 | Integridad | La desactivación manual no elimina registros. El `Member` y los `Residency` pasan a estado `inactive` conservando el historial y el motivo de desactivación |
| BR-039 | Onboarding | Tras la desactivación de un `household_admin`, cualquier nuevo residente puede hacer onboarding en ese domicilio siguiendo el flujo normal, sin pasos adicionales |
| BR-040 | Residencia | Un `HouseholdUnit` (dirección física) puede contener múltiples `FamilyGroup`, cada uno representando un núcleo familiar distinto que convive en esa dirección (ej: dos familias en la misma casa, o un adulto mayor independiente) |
| BR-041 | Residencia | Cada `FamilyGroup` tiene su propio `household_admin` que gestiona únicamente sus residentes dependientes. No puede editar ni ver los residentes de otro `FamilyGroup` dentro del mismo `HouseholdUnit` |
| BR-042 | Residencia | Un `household_admin` puede visualizar qué otros `FamilyGroup` existen en su mismo `HouseholdUnit`, pero solo en modo lectura, para tener contexto de quiénes conviven en el domicilio |
| BR-043 | Onboarding | Cuando el admin aprueba un onboarding en una dirección ya existente, vincula al solicitante al `HouseholdUnit` existente creando un nuevo `FamilyGroup` dentro de él. Si la dirección es nueva, crea tanto el `HouseholdUnit` como el `FamilyGroup` |
| BR-056 | Integridad | `FamilyGroup` es un modelo nuevo que debe crearse. Representa un núcleo familiar dentro de un `HouseholdUnit`. `HouseholdUnit` conserva su rol como dirección física. `FamilyGroup` pertenece a `HouseholdUnit` y contiene al `household_admin` y sus residentes dependientes. Pendiente de implementar |
| BR-044 | Identidad | Cada junta verifica los documentos de identidad de forma independiente, siempre. Que un RUN ya exista verificado en otra junta es solo informativo para el admin, no exime de la verificación |
| BR-045 | Identidad | El sistema no controla la vigencia de los documentos de identidad. Un `Member` activo opera con normalidad aunque su carnet haya vencido. La vigencia documental queda a criterio del admin de la junta |
| BR-046 | Identidad | Para corregir un RUN erróneo en una `VerifiedIdentity` aprobada: el admin desactiva al socio (BR-036) y el socio realiza un nuevo onboarding con el RUN correcto. No existe edición directa del RUN post-aprobación |
| BR-047 | Onboarding | Una solicitud rechazada permanece en el historial del usuario con el motivo de rechazo visible. No se destruye ni archiva |
| BR-048 | Onboarding | El usuario puede iniciar una nueva solicitud de onboarding tras un rechazo. Tiene la opción de "duplicar" la solicitud rechazada para pre-cargar todos sus datos y solo corregir lo necesario, sin empezar desde cero |
| BR-049 | Onboarding | Al duplicar una solicitud rechazada, se crea una nueva `OnboardingRequest` en estado `draft` con los datos copiados. La solicitud original rechazada permanece intacta en el historial |
| BR-050 | Onboarding | El sistema envía un recordatorio-resumen diario por email a cada admin de la junta mientras tenga solicitudes en estado `pending` sin revisar. Un solo correo por admin agrupa todas las pendientes de su junta (sin spam por solicitud). Implementado vía `OnboardingRemindersJob` (recurrente en `config/recurring.yml`, `every day at 8am`) + `OnboardingReminderMailer#pending_digest` |
| BR-051 | Onboarding | El usuario puede cancelar su solicitud en estado `pending` en cualquier momento desde su panel, quedando libre para iniciar una nueva solicitud o duplicar la cancelada |
| BR-052 | Acceso | Una junta de vecinos puede tener múltiples usuarios admin simultáneos. Cualquiera de ellos puede revisar y gestionar todas las solicitudes pendientes de la junta |
| BR-053 | Acceso | Al dar de baja a un admin, las solicitudes pendientes permanecen intactas y disponibles para los demás admins de la junta. El superadmin puede asignar nuevos admins en cualquier momento |
| BR-054 | Multi-tenant | Cuando una junta se disuelve, el superadmin la marca como `inactive`. Todos sus `Member` activos pasan a `inactive` en cascada |
| BR-055 | Multi-tenant | La disolución de una junta no migra socios automáticamente. Cada socio decide individualmente si hace onboarding en otra junta. El historial de certificados e identidad se conserva |
| BR-057 | Identidad | Un RUN ya verificado puede aparecer en un nuevo onboarding con una cuenta de usuario distinta (ej: el residente perdió acceso a su cuenta anterior). El sistema lo permite y alerta al admin durante la revisión |
| BR-058 | Identidad | Mientras el nuevo onboarding con un RUN duplicado no sea aprobado, la membresía anterior asociada a ese RUN permanece activa e intacta. El admin es el único que puede validar si se trata de la misma persona legítima |
| BR-059 | Identidad | Solo cuando el admin aprueba el onboarding con un RUN duplicado, el `Member` anterior asociado a ese RUN pasa a estado `inactive`. La aprobación es el acto que transfiere la identidad verificada a la nueva cuenta |
| BR-060 | Identidad | Si el admin rechaza un onboarding con RUN duplicado, la membresía anterior continúa activa sin ningún cambio. El admin debe registrar el motivo del rechazo, especialmente si detecta un intento de fraude |
| BR-061 | Certificados | Un socio verificado puede solicitar tantos certificados como desee, sin restricciones por cantidad ni por estados de solicitudes previas. Certificados en `pending_payment` o pagados sin usar son responsabilidad del usuario |
| BR-062 | Certificados | Una vez que el admin aprobó el onboarding del socio (identidad + domicilio verificados), los certificados se emiten automáticamente tras el pago confirmado. No requieren revisión ni aprobación del admin por cada solicitud |
| BR-063 | Certificados | No existe posibilidad de rechazo de un certificado post-verificación. Por lo tanto no hay devoluciones de pago. El pago es el último paso antes de la emisión automática |
| BR-064 | Certificados | Los estados del certificado se simplifican a: `pending_payment` → `paid` → `issued`. Los estados `approved` y `rejected` quedan eliminados del flujo de certificados |
| BR-065 | Residencia | El `household_admin` puede registrar residentes dependientes (menores de edad) en su `FamilyGroup` sin que estos tengan cuenta de usuario. Se modela como `IdentityVerificationRequest(dependent: true)` con `family_group_id`, `requested_by_id` y `neighborhood_association_id` |
| BR-066 | Identidad | El admin de la junta debe verificar la identidad del dependiente con documentación antes de aprobarlo, igual que en el onboarding estándar. Las solicitudes dependientes aparecen en `admin/dependent_reviews`, separadas del flujo normal de onboarding |
| BR-067 | Residencia | Al aprobar un dependiente, en una sola transacción se crea `VerifiedIdentity` + `Member(dependent: true, status: approved)` + `Residency(household_admin: false, status: approved)` heredando la `VerifiedResidence` del `HouseholdUnit` del `FamilyGroup` del padre |
| BR-068 | Identidad | El teléfono es opcional para dependientes (menores pueden no tenerlo). Las demás validaciones (RUN normalizado y dígito verificador, nombre y apellido) aplican igual que para identidades independientes |
| BR-069 | Identidad | Cuando un dependiente crece y hace su propio onboarding en cualquier junta, el mecanismo existente de RUN duplicado (BR-057-059) detecta la coincidencia. Al aprobar el nuevo onboarding, el `Member(dependent: true)` anterior pasa a `inactive` automáticamente — la graduación no requiere lógica nueva |
| BR-070 | Precios | Cada junta puede definir múltiples precios históricos con vigencia (`effective_from`, `effective_to`). El precio efectivo de un certificado es el vigente al momento de crear el `ResidenceCertificate` y queda capturado en `amount` (snapshot inmutable). Crear un nuevo precio cierra automáticamente la vigencia del anterior |
| BR-071 | Pagos | El webhook de MercadoPago es idempotente: si llega dos veces con el mismo `payment_id`, no se procesa dos veces ni se actualiza el certificado. Implementado vía índice único en `residence_certificates.payment_id` + chequeo explícito en el controller |
| BR-072 | Pagos | El webhook de MercadoPago debe validar la firma `x-signature` (HMAC-SHA256 con `webhook_secret`) antes de procesar. Webhooks sin firma válida son descartados con `401 Unauthorized` |
| BR-073 | Pagos | Si el pago es rechazado, refunded o cancelado por MP, el certificado vuelve/permanece en `pending_payment`. El usuario puede reintentar pagando desde la UI (BR-003). El webhook no degrada un certificado ya `issued` |
| BR-074 | Certificados | El `validation_token` (UUID) y `validation_code` (alfanumérico de 8 caracteres, sin 0/O/1/I para evitar confusión visual) se generan al emitir el certificado y son únicos en la base de datos. El código se usa para verificación manual/telefónica; el token para el QR |
| BR-075 | Certificados | El PDF se genera una sola vez al emitir y se almacena vía Active Storage (`pdf_document`). Descargas posteriores reutilizan el archivo almacenado |
| BR-076 | Certificados | La transición `paid → issued` se ejecuta en un job asíncrono (`IssueCertificateJob`) disparado tras confirmar el pago vía `after_commit`. Si la generación del PDF falla, el job reintenta hasta 3 veces con backoff polinomial; si todos fallan, el certificado queda en `paid` para revisión manual |
| BR-077 | Certificados | Eliminada la acción manual `Admin::ResidenceCertificatesController#issue`. La emisión es exclusivamente automática (BR-062). El admin ya no puede forzar emisión sin pago |
| BR-078 | Validación | El RUN del titular se muestra parcialmente oculto en la verificación pública (formato `1.XXX.XXX-K`) para proteger privacidad. La verificación pública no expone datos completos del titular |
| BR-079 | Validación | El endpoint `/verify/:identifier` acepta el `validation_token` (UUID) o el `validation_code` (8 chars alfanumérico, case-insensitive). Ambos resuelven al mismo certificado vía `ResidenceCertificate.find_for_public_verification` |
| BR-080 | Validación | Un certificado con `expiration_date < today` se muestra como **Vencido** con response 200 OK (cumple BR-009 — URL responde indefinidamente). Solo identificadores **inexistentes** o certificados no-`issued` retornan 404 |
| BR-081 | Validación | La verificación pública nunca expone certificados que no estén en estado `issued`. El scope `findable_publicly` filtra automáticamente; el controller no puede ser engañado vía URL para mostrar certs en `pending_payment` o `paid` |
| BR-082 | Residencia | El registro de convivientes del domicilio se realiza exclusivamente vía el flujo de residentes dependientes (BR-065 a BR-069). El antiguo flujo "Socios del Domicilio" (`panel/members`) fue eliminado en 2026-07-22: estaba incompleto (creaba `Residency` en `pending` sin revisión admin posible y sin `Member`, rompiendo BR-027 al solicitar certificados) y duplicaba la funcionalidad de dependientes |
| BR-083 | Pagos | Para habilitar una publicación del marketplace el usuario debe pagar vía MercadoPago (mismo mecanismo Checkout Pro que los certificados). Estados de publicación: `pending_payment` → `published`. Solo el webhook con pago `approved` publica; pagos rechazados/pendientes no cambian el estado |
| BR-084 | Precios | Cada junta define el precio de habilitación de publicaciones con vigencias históricas (`ListingPricing`, espejo de BR-070). Mínimo $1.000 CLP. El monto se captura en `amount` (snapshot) al iniciar el pago. Para pagar, el usuario debe ser socio activo de una junta y esa junta debe tener precio vigente |
| BR-085 | Comisión | Yuntapp retiene el 10% del pago de cada publicación (`platform_fee`); el 90% es para la junta del socio, registrada como snapshot en `listings.neighborhood_association_id` |
| BR-086 | Pagos | La publicación queda vigente 30 días desde el pago (`published_until`). Al vencer puede renovarse con un nuevo pago, que otorga 30 días desde el nuevo pago. Las publicaciones existentes antes del cobro recibieron 30 días de gracia en la migración |
| BR-087 | Pagos | El webhook de MercadoPago es compartido entre certificados y publicaciones: `external_reference` con prefijo `listing-<id>` enruta a `Listing`; un id a secas enruta a `ResidenceCertificate` (formato original). La idempotencia por `payment_id` (BR-071) se verifica contra ambas tablas |
| BR-088 | Pagos | Las publicaciones pueden auto-renovarse vía Suscripciones de MercadoPago (`preapproval`, frecuencia mensual), opcional al pago único. El monto queda fijo al autorizar (snapshot del precio vigente); si la junta cambia su precio, las suscripciones vigentes mantienen el monto antiguo — para tomar el nuevo, el usuario debe cancelar y volver a suscribirse. El usuario puede cancelar en cualquier momento desde su panel |
| BR-089 | Pagos | Cada cobro recurrente aprobado (webhook `subscription_authorized_payment`) extiende la vigencia 30 días desde el vencimiento vigente si la publicación está al día, o desde la fecha del cobro si estaba vencida. Cancelar la suscripción no corta la vigencia ya pagada: la publicación vence normalmente. Si el cobro recurrente falla, la publicación simplemente vence (BR-086) sin degradarse antes |

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

---

## Stack Tecnologico

- **Ruby**: 3.4.8
- **Rails**: 8.1.1
- **Base de datos**: SQLite3
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS, DaisyUI
- **Asset Pipeline**: Propshaft + Importmap (sin Webpack/esbuild)
- **Autenticacion**: Devise (rama main de GitHub)
- **Paginacion**: Pagy
- **Deploy**: Kamal con Docker, Thruster para HTTP acceleration
- **Background Jobs**: Solid Queue
- **Cache**: Solid Cache
- **WebSockets**: Solid Cable
- **Tests**: Minitest con fixtures, SimpleCov para cobertura
- **Linting**: Standard Ruby (`standardrb`), ERB Lint

## Estructura de Directorios

```
app/
  controllers/
    admin/          # Panel de administracion de junta vecinal
    panel/          # Panel del usuario/socio
    superadmin/     # Panel de superadministrador del sistema
    users/          # Controladores Devise personalizados
    concerns/
  models/
    concerns/       # Filterable, Sortable
  views/
    admin/          # Vistas admin (board_members, dashboard, household_units, etc.)
    panel/          # Vistas panel usuario (onboarding, dashboard, listings, etc.)
    superadmin/     # Vistas superadmin
    layouts/        # application, admin, superadmin, auth, panel
    shared/         # _flash.html.erb
  validators/       # RunValidator, PhoneValidator
  helpers/
  javascript/
    controllers/    # Stimulus controllers
config/
  locales/          # en.yml, es.yml, devise.en.yml
db/
  migrate/
  schema.rb
test/
  controllers/
  models/
  fixtures/
```

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

## Modelo de Datos

### Jerarquia Geografica
```
Country -> Region -> Commune -> NeighborhoodAssociation -> NeighborhoodDelegation -> HouseholdUnit
```

### Entidades Principales

#### User
- Devise: database_authenticatable, registerable, confirmable, recoverable, rememberable, validatable
- Flags: `admin`, `superadmin`
- Pertenece a: `neighborhood_association` (opcional), `verified_identity` (opcional)
- Tiene: `onboarding_requests`, `identity_verification_requests`, `residence_verification_requests`, `listings`
- `current_onboarding_request`: solicitud en estado draft/pending
- Metodo `member`: primer member de su verified_identity
- Metodo `name`: nombre de verified_identity o email

#### VerifiedIdentity
- Campos: `first_name`, `last_name`, `run` (unico), `phone`, `email`, `verification_status`
- Status: pending | verified | rejected
- Attachment: `identity_document` (Active Storage)
- Callbacks: `normalize_run_field` (formato XX.XXX.XXX-K), `normalize_names` (capitaliza), `normalize_phone` (formato +56)
- Validadores custom: `RunValidator`, `PhoneValidator`

#### OnboardingRequest
- Status: draft | pending | approved | rejected
- Pertenece a: `user`, `neighborhood_association`, `region`, `commune`
- Tiene uno: `identity_verification_request`, `residence_verification_request`

#### IdentityVerificationRequest
- Status: draft | pending | approved | rejected
- Campos: `first_name`, `last_name`, `run`, `phone`, `rejection_reason`
- Attachments: `identity_documents` (muchos)
- Callbacks de normalizacion iguales a VerifiedIdentity

#### ResidenceVerificationRequest
- Status: pending | approved | rejected
- Campos de direccion + `manual_address` (boolean) + `neighborhood_delegation_id`
- Validacion condicional: requiere delegation_id o address_line_1

#### Member
- Vincula `VerifiedIdentity` con `HouseholdUnit`
- Status: pending | approved | rejected
- Flags: `household_admin`
- Trazabilidad: `requested_by` (User), `approved_by` (User), `approved_at`
- Delega name, run, phone, email, first_name, last_name a verified_identity
- Tiene: `board_members`, `residence_certificates`, `documents` (attachments)

#### HouseholdUnit
- Representa la dirección física. Relación 1:1 con un domicilio real
- Puede contener múltiples `FamilyGroup` (BR-040)
- Pertenece a: `neighborhood_delegation`, `commune`
- Campos de dirección completos

#### FamilyGroup _(modelo nuevo — BR-056)_
- Representa un núcleo familiar dentro de un `HouseholdUnit`
- Pertenece a: `HouseholdUnit`
- Tiene un `household_admin` (el `Member` que gestiona el grupo)
- Tiene muchos residentes dependientes (`Residency` con `household_admin: false`)
- Un `household_admin` solo puede gestionar su propio `FamilyGroup`

#### ResidenceCertificate
- Status: pending_payment | paid | issued (BR-064 — los estados `approved`/`rejected` fueron eliminados del flujo)
- Campos: `folio` (unico por asociacion), `issue_date`, `expiration_date`, `purpose`, `notes`
- Campos de pago/validación (implementados): `amount` (precio en CLP, snapshot inmutable — BR-070), `platform_fee` (10% de amount), `payment_id` (referencia MercadoPago, único — BR-071), `validation_token` (UUID para la URL pública), `validation_code` (8 chars alfanuméricos sin 0/O/1/I — BR-074)
- `generate_folio!`: formato "CR-{association_id}-{sequence}"
- `mark_as_paid!` (idempotente, pending_payment → paid) e `issue!` (paid → issued) en `app/models/residence_certificate.rb`
- Emisión automática tras el pago vía `IssueCertificateJob` (after_commit, 3 retries — BR-076). El PDF con QR + código + URL se genera con `CertificatePdfService` y se guarda en Active Storage `pdf_document` (BR-075)
- Verificación pública vía `find_for_public_verification` + scope `findable_publicly` (BR-079/BR-081)

#### CertificatePricing _(BR-070)_
- Precio histórico de certificados por junta, con vigencia: `price`, `effective_from`, `effective_to`
- `CertificatePricing.current_for(association)`: precio vigente. Crear un precio nuevo cierra la vigencia del anterior
- El `amount` del `ResidenceCertificate` captura el precio vigente al momento de crearse (snapshot inmutable)

#### BoardMember
- Posiciones: presidente | secretario | tesorero | director
- Campos: `position`, `start_date`, `end_date`, `active`

#### Listing (Marketplace)
- Pertenece a: `user`, `category` (opcional), `neighborhood_association` (opcional, snapshot al pagar — BR-085)
- Campos: `name`, `description`, `price`, `active`
- Publicación pagada (BR-083/BR-086): `publication_status` (`pending_payment` | `published`), `amount` (snapshot del precio de la junta), `platform_fee` (10%), `payment_id` (único), `paid_at`, `published_until` (pago + 30 días)
- `mark_as_paid!` (idempotente, BR-087) publica por 30 días; renovación tras vencimiento con nuevo pago
- Auto-renovación (BR-088/BR-089): `preapproval_id` (único), `subscription_status` (`pending` | `authorized` | `paused` | `cancelled`). `renew_from_subscription!` extiende la vigencia con cada cobro recurrente aprobado. Controlador `Panel::ListingSubscriptionsController` (suscribir/cancelar); webhooks `subscription_preapproval` y `subscription_authorized_payment`

#### ListingPricing _(BR-084)_
- Precio histórico por junta para habilitar publicaciones, con vigencia (`price`, `effective_from`, `effective_to`) — espejo de `CertificatePricing`
- `ListingPricing.current_for(association)`: precio vigente. Mínimo $1.000 CLP. Gestionado en `admin/listing_pricings`

### Concerns

- **Filterable**: Incluido en ApplicationRecord. Provee `filter_by_id(ids)` y `filter_by_name(name)` con LIKE.
- **Sortable**: Incluido en ApplicationRecord. Provee scopes `sort_by_{column}(direction)` para id, name, active, created_at, position, status, folio, member_id.

## Validadores Custom

- **RunValidator** (`app/validators/run_validator.rb`): Valida formato RUN chileno (`\d{7,8}-[\dkK]`) y digito verificador con algoritmo modulo 11.
- **PhoneValidator** (`app/validators/phone_validator.rb`): Valida formato telefono chileno (`+569XXXXXXXX`).

## Frontend

### Stimulus Controllers
- **autosave_controller**: Auto-envia formularios tras un delay configurable (default 2s). Usado en onboarding para guardar campos individuales via Turbo Streams.
- **cascading_select_controller**: Selects en cascada Region -> Comuna -> Asociacion. Carga datos completos como JSON en un value de Stimulus para evitar requests extra.
- **manual_address_controller**: Alterna entre select de delegacion e input de direccion manual con checkbox.

### Turbo Streams
Uso extensivo en el onboarding para actualizar campos individuales sin recargar la pagina. Patron: PATCH envia campo -> controlador valida -> responde con `turbo_stream.replace` del campo y boton de submit.

### CSS
- Tailwind CSS via `tailwindcss-rails` gem
- DaisyUI como libreria de componentes (temas, drawer, alerts, badges, etc.)
- Tema fijo: `data-theme="light"`

### Layouts
- `application.html.erb`: Layout publico general
- `auth.html.erb`: Login/registro (centrado, minimalista)
- `admin.html.erb`: Panel admin con drawer sidebar
- `superadmin.html.erb`: Panel superadmin con sidebar
- `panel.html.erb`: Panel de usuario

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
- Tests de modelos y controladores.
- SimpleCov para cobertura de codigo.
- Ejecutar tests: `bin/rails test`
- Ejecutar test especifico: `bin/rails test test/models/user_test.rb`

## Comandos Utiles

```bash
# Servidor de desarrollo
bin/dev                          # Inicia con Procfile.dev (rails + tailwind watch)
bin/rails server                 # Solo Rails

# Base de datos
bin/rails db:migrate             # Ejecutar migraciones
bin/rails db:seed                # Cargar datos semilla
bin/rails db:schema:load         # Cargar schema desde cero

# Tests
bin/rails test                   # Todos los tests
bin/rails test test/models/      # Tests de modelos
bin/rails test test/controllers/ # Tests de controladores

# Linting
bin/standardrb                   # Standard Ruby (linter principal)
bin/standardrb --fix             # Auto-corregir estilo
bundle exec erb_lint --lint-all  # ERB Lint (templates)

# Deploy
kamal setup                      # Setup inicial
kamal deploy                     # Deploy con Kamal
```

## Deploy

- Docker con Kamal para despliegue en VPS.
- Archivo `Dockerfile` incluido con build multi-stage.
- Configuracion en `config/deploy.yml` y `config/deploy.local.yml` para simulacion local.
- `LOCAL_DEPLOY.md` documenta como simular deploy en local con Docker.
- Thruster como proxy HTTP para caching y compresion.

## Idioma

La aplicacion esta primariamente en espanol (interfaz, mensajes flash, labels de formularios). Los archivos i18n estan en `config/locales/es.yml` y `config/locales/en.yml`. Las vistas del admin, panel y onboarding usan traducciones i18n extensivamente.

## Agent Team Configuration

> **OBLIGATORIO:** Para cualquier tarea de codigo (feature, fix, refactor, UI), seguir este workflow sin que el usuario lo pida.

### Archivos compartidos (`.claude/team/`)

```
backlog.md                 # Tareas pendientes
current-sprint.md          # Sprint actual
architecture/decisions.md  # ADRs
reviews/pending.md         # PRs en revision
bugs/active.md             # Bugs activos
```

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
4. Documentar decisiones en `decisions.md`
5. Usar IDs unicos: `BUG-XXX`, `ADR-XXX`, `#XXX`

### Skills disponibles

| Skill | Descripcion |
|-------|-------------|
| `/dev` | Pipeline autonomo: clasifica prompt → branch → implementa → review → PR |
| `/feature` | Feature completa con planning, mini-audit y actualizacion de equipo |
| `/review` | Revisa branch actual: seguridad, N+1, tests, veredicto APROBADO/CAMBIOS/BLOQUEADO |
| `/security` | Revision de seguridad Rails: strong params, autorizacion entre asociaciones, XSS, SQL injection |
| `/tdd` | Workflow TDD con Minitest y fixtures: tests primero, patron Arrange-Act-Assert |
| `/deploy` | Deploy con Kamal: pre-checklist, migraciones, health checks y rollback |
| `/db-migrate` | Crea y aplica migraciones Rails con checklist de indices, null constraints, expand-contract y batch |
| `/fix-issues` | Resuelve GitHub issues creando un PR por cada uno |
| `/audit` | Auditoria integral del codebase |
| `/audit-to-issues` | Convierte hallazgos de auditoria en GitHub issues |
| `/merge-pr` | Mezcla PRs aprobados con squash merge |
| `/check-code` | Ejecuta todas las validaciones de calidad |
