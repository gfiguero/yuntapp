# Auditoría — Ciclo de vida del certificado de residencia

Alcance: solicitud/emisión, `IssueCertificateJob`, folio estructurado (BR-006), `CertificatePdfService`,
verificación pública, vencimiento/descarga, titularidad multi-núcleo (BR-041/BR-098), notificaciones.
Código auditado: `master` @ `259e22c`. No se repiten hallazgos ya remediados de
`docs/2026-07-30-auditoria-profunda.md` salvo para confirmar su cierre.

---

### [SEVERIDAD: Crítica] Un `household_admin` ve y descarga los certificados de OTRO núcleo familiar que comparte su misma dirección

- **Archivo:** `app/controllers/panel/residence_certificates_controller.rb:11-13` (`index`), `:95-97` (`set_residence_certificate`, usado por `show` y `download`)
- **Regla:** BR-041 (aislamiento entre `FamilyGroup` de un mismo `HouseholdUnit`), BR-098, BR-147
- **Qué está mal:** El PR #159 (commit `7acc76d`, "aísla los núcleos familiares que comparten domicilio") corrigió el filtro por `FamilyGroup` únicamente en `selectable_residencies` (quién puede ser **titular** de un certificado nuevo). Pero `index` y `set_residence_certificate` — que gobiernan **ver y descargar certificados ya emitidos** — siguen scopeados solo por `household_unit`:
  ```ruby
  def index
    @residence_certificates = ResidenceCertificate.where(household_unit: current_user.household_unit)...
  end
  def set_residence_certificate
    @residence_certificate = ResidenceCertificate.where(household_unit: current_user.household_unit).find(params[:id])
  end
  ```
  Como un `HouseholdUnit` es una dirección física que puede alojar varios `FamilyGroup` sin relación entre sí (BR-040), el `household_admin` de un núcleo ve en "Mis certificados" — y puede abrir/descargar — los certificados emitidos para el otro núcleo que vive en el mismo domicilio: nombre completo del titular, propósito (a menudo sensible: "pensión de alimentos", "trámite bancario", etc.), monto pagado y el PDF completo (con el RUN **sin enmascarar**, a diferencia de la verificación pública que sí lo oculta — BR-078 no aplica al panel).
- **Cómo lo verifiqué:** Reproduje el escenario con un test de integración desechable (creado, ejecutado y borrado en esta sesión, sin dejar cambios en el árbol — `git status` limpio al finalizar). Usé el mismo helper `residente_de_otro_nucleo` que ya existe en `test/controllers/panel/residence_certificates_controller_test.rb` (creado en el propio PR #159 para el escenario de creación, pero nunca reusado para `index`/`show`/`download`). Con un segundo `household_admin` (`Zeratul`) en un `FamilyGroup` distinto del mismo `HouseholdUnit` (`Selendis`):
  ```
  INDEX incluye cert ajeno? true
  SHOW status para cert ajeno: 200
  DOWNLOAD status para cert ajeno: 200, content_type=application/pdf
  ```
  El PDF completo del certificado de la familia Selendis se descarga con la sesión de Zeratul. Confirmé también que ningún test existente cubre este camino: solo hay dos tests con `residente_de_otro_nucleo`, ambos sobre el selector/`create`.
- **Impacto en go-live:** **Bloquea.** Es exactamente el mismo patrón de filtración que el propio equipo identificó como crítico hace dos días (PR #159) — la mitad del arreglo no se aplicó. Con clientes reales, cualquier domicilio con dos familias (edificios, sitios con "casa + mediagua", allegados) expone documentos oficiales con datos personales de una familia a la otra. Es trivialmente explotable por cualquier vecino con cuenta legítima, no requiere manipular params.
- **Fix sugerido:** Scopear `index` y `set_residence_certificate` por el `FamilyGroup` del solicitante, igual que `selectable_residencies` — p. ej. `ResidenceCertificate.where(member: current_user.family_group_member_ids)` derivando el titular vía `member.verified_identity.residencies` con `family_group_id == current_user.family_group.id`, o agregando una columna `family_group_id` directa al certificado (más simple y auditable, similar a por qué se agregó `requested_by_id` en BR-152). Agregar un test de `index`/`show`/`download` con `residente_de_otro_nucleo` — ya existe el fixture helper, solo falta usarlo aquí.

---

### [SEVERIDAD: Alta] El correo de "certificado emitido" para un dependiente llega al admin que aprobó su registro, no al household_admin que lo pidió y pagó

- **Archivo:** `app/mailers/residence_certificate_mailer.rb:6-11` (`recipient_email = certificate.member.user&.email`), `app/models/member.rb:34-36` (`def user`), `app/controllers/admin/dependent_reviews_controller.rb:75` (`requested_by: current_user`)
- **Regla:** UC-005 (postcondición: "el socio recibe notificación"), BR-098, falta regla explícita sobre el destinatario del correo de emisión
- **Qué está mal:** `ResidenceCertificateMailer#issued` resuelve el destinatario vía `certificate.member.user`, y el propio comentario del archivo dice que para dependientes esto "returns requested_by" — asumiendo que `Member#requested_by` es el `household_admin` que gestiona al dependiente. Pero `Member#requested_by` para un dependiente se fija en `Admin::DependentReviewsController#approve:75` como `current_user`, que en ese controller es **el admin de la junta que aprueba la solicitud**, no el `household_admin` que la envió (ese dato sí existe, correcto, en `IdentityVerificationRequest#requested_by`, seteado en `Panel::DependentsController#create`, pero nunca se propaga al `Member` en la aprobación). El propio `DemoJuntaSeeder` (línea 128) resuelve esto correctamente para su caso de análisis (`admin_residency`→`User`), lo que confirma que el patrón correcto es conocido pero no se aplicó en el controller real.
- **Cómo lo verifiqué:** Test desechable (`test/mailers/zz_audit_recipient_test.rb`, ejecutado y borrado, árbol limpio al terminar) que replica exactamente los pasos de `DependentReviewsController#approve` y arma el mail:
  ```
  IVR.requested_by (household_admin real): selendis@daelaam.io
  Member.requested_by (guardado por el controller): admin_revisor_audit@example.com
  Member#user (usado por el mailer): admin_revisor_audit@example.com
  Coincide con household_admin real? false
  Mailer 'to': ["admin_revisor_audit@example.com"]
  Debería ser: [selendis@daelaam.io]
  ```
- **Impacto en go-live:** Alto pero no bloqueante por sí solo — no bloquea la emisión ni el pago, pero rompe la experiencia central del producto para el caso BR-098 (household_admin pidiendo el certificado de un adulto mayor o dependiente a su cargo, el caso que la regla dice ser "crítico"): el vecino que pagó nunca se entera de que su documento está listo salvo que vuelva a entrar al panel por su cuenta, y el correo va a parar a la bandeja de un admin de junta con un enlace de descarga a un documento de un tercero (dependiendo del admin, puede o no ser la misma persona que ya tiene acceso legítimo vía el panel admin — no es una fuga de autorización nueva, pero sí un envío claramente errado). Con el primer certificado real a punto de emitirse, cualquier solicitud a nombre de un dependiente dispara este bug de inmediato.
- **Fix sugerido:** Usar `certificate.requested_by` (columna ya existente desde BR-152, poblada siempre desde la sesión en `Panel::ResidenceCertificatesController#create`) como fuente primaria del destinatario, con fallback a `certificate.member.user` solo para certificados anteriores a esa columna (`requested_by_id` es nullable). Alternativamente, corregir `Admin::DependentReviewsController#approve` para propagar `requested_by: @dependent_request.requested_by` al crear el `Member`, aunque el fix por `certificate.requested_by` es más directo y ya está disponible.

---

### [SEVERIDAD: Baja] Folio estructurado (BR-006): diseño sólido, pero sin test end-to-end de colisión concurrente real

- **Archivo:** `app/models/residence_certificate.rb` (`issue!`, `next_folio_sequence`, `folio_collision?`)
- **Regla:** BR-006, #98
- **Qué está mal:** Revisé con ojo fresco la migración nueva (`20260821032041_add_folio_components_to_residence_certificates.rb`) y el backfill (`20260821032052_backfill_folio_components.rb`). El índice único parcial `(neighborhood_association_id, folio_year, folio_sequence) WHERE folio_sequence IS NOT NULL` existe y es correcto; el índice legado `(neighborhood_association_id, folio)` también se mantiene. `with_lock` en `issue!` serializa reintentos sobre el **mismo** certificado, pero la protección real contra dos certificados **distintos** de la misma junta emitiéndose en paralelo depende enteramente del índice único + retry (`FOLIO_MAX_ATTEMPTS = 5`), no de `with_lock` (que no bloquea entre filas distintas). El diseño es correcto y los tests unitarios mockean la colisión (`define_singleton_method(:next_folio_sequence)`) y pasan — verifiqué corriendo `bin/rails test test/models/residence_certificate_test.rb` (74 runs, 0 failures). Backfill: como la base de producción no tiene certificados (se borraron ayer, ver `docs/`), no hay folios legado que backfillear — el arranque en 1 está garantizado.
- **Cómo lo verifiqué:** Lectura de migraciones + `db/schema.rb`, corrida de la suite de tests del modelo.
- **Impacto en go-live:** No bloquea. El mecanismo es correcto por diseño; solo falta (deuda, no bug) un test de integración con hilos/conexiones reales que ejercite la colisión sin mockear `next_folio_sequence`, dado que SQLite en producción tiene semántica de bloqueo distinta a un test unitario de un solo hilo.
- **Fix sugerido:** Opcional — test con `Thread`/conexiones concurrentes reales contra SQLite, o aceptar el riesgo residual dado que el volumen de emisión por junta es bajo (vecinal, no masivo).

---

### Áreas revisadas sin hallazgos nuevos

- **`IssueCertificateJob`**: idempotente (`return if certificate.issued? && pdf attached`), reingresa si quedó `issued` sin PDF, notifica al staff tras agotar 3 reintentos (BR-148, verificado en `CertificateIssuanceFailureMailer`). Correcto.
- **`issue!` bajo reversión concurrente (BR-141)**: `with_lock` recarga antes de decidir; test explícito (`issue! aborta si el pago fue revertido concurrentemente`) pasa.
- **`CertificatePdfService`**: generé PDFs de prueba (fuera de la app, sin persistir) con nombres muy largos (250+ caracteres, una sola palabra), caracteres especiales (tildes, ñ, ¡¿, apóstrofes, guiones), y domicilio sin comuna/calle — en todos los casos el PDF se generó sin error y el texto se renderiza legible (verificado con `pdftotext`). El QR apunta a `verification_base_url` (`config/initializers/verification_url.rb`), que exige `YUNTAPP_HOST`/credentials en producción con warning si falta — correcto y ya endurecido (#102).
- **Verificación pública (`/verify/:identifier`)**: `findable_publicly` filtra a `issued`; precedencia `holder_deactivated? > payment_reverted? > expired?` correcta y con textos distintos (BR-091/BR-141/BR-092); 200 siempre salvo identificador inexistente (BR-009/BR-080); `masked_run` ya fue endurecido a fallo-cerrado (`FULLY_MASKED_RUN`, commit `60e1b35`) — confirmado en el código actual.
- **Vencimiento y descarga (BR-023, BR-092, BR-147)**: `VALIDITY_PERIOD = 30.days`; `download` en el panel usa `send_data` tras `downloadable?` (ya no `redirect_to rails_blob_path`) — el hallazgo Alto de la auditoría de julio está cerrado, confirmado leyendo el controller actual y su comentario explicativo.
- **Junta sin RUT (BR-120/BR-148)**: guard `ensure_association_constituted!` en `new`/`create` del panel de certificados y en `PaymentsController`; `issue!` también aborta. Cerrado.
- **Admin de certificados**: solo lectura, scopeado a `current_neighborhood_association` (BR-007), sin `destroy`/`issue` manual (BR-077 — columna `approved_by_id` ya eliminada, confirmado `ResidenceCertificate.column_names` sin ella).
- **Webhook MP → certificado**: validación de monto (BR-090), idempotencia por `(payment_id, status)` (BR-071/BR-146), reversión definitiva por pago (BR-146) — sin cambios desde la auditoría de julio, sigue correcto.

---

## Resumen

**1 Crítica · 1 Alta · 1 Baja.**

- Crítica: Un `household_admin` ve y descarga los certificados de OTRO núcleo familiar que comparte su misma dirección
- Alta: El correo de "certificado emitido" para un dependiente llega al admin que aprobó su registro, no al household_admin que lo pidió y pagó
