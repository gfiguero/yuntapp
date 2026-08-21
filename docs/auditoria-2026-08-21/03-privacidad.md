# Auditoría de privacidad y exposición de datos personales — yuntapp

**Fecha:** 2026-08-21 · **Commit auditado:** `259e22c` (master) · **Alcance:** qué datos personales
puede ver quién, y qué se escapa. Ley 19.628 (Chile); el RUN, el domicilio exacto y las fotos de
cédula son los activos protegidos.

**Método:** lectura de los 58 controladores, sus vistas y los modelos implicados; verificación de
configuración *en producción* vía `bin/rails runner` de solo lectura contra
`143.198.120.175`; contraste con `docs/2026-07-30-auditoria-profunda.md` para no repetir lo
remediado.

**Estado de producción al momento de auditar** (leído con runner):
`{users: 26, members: 20, identities: 20, certs: 0, household_units: 15, family_groups: 15,
hu_with_multiple_family_groups: {}, associations: 1, admins: 1, blobs: 28}`.
Es decir: **28 blobs de documentos de identidad/domicilio ya almacenados**, ningún domicilio
compartido por dos núcleos todavía, y una sola junta. Nada de lo que sigue se ha materializado aún
como fuga real — todo lo que sigue se materializa el día que entren vecinos reales.

**Resumen:** 1 Crítica · 3 Altas · 5 Medias · 7 Bajas.

**Hallazgos previos (2026-07-30) que revisé y confirmo remediados:** vitrina pública sobre
`Listing.published` (BR-143), `masked_run` falla cerrado (BR-078), descarga del PDF con `send_data`
+ `urls_expire_in = 5.minutes` (BR-147), `:run` excluido en `admin/members#update` (BR-046),
`BoardMember` valida la junta del socio (BR-007). **Sigue vigente** el ítem Baja «`Admin::UsersController`
es código muerto»: ya no existe el archivo, así que ese sí quedó cerrado.

---

## Crítica

### [SEVERIDAD: Crítica] Un jefe de hogar ve y descarga el certificado —con RUN completo y domicilio— de otro núcleo familiar del mismo domicilio
- **Archivo:** `app/controllers/panel/residence_certificates_controller.rb:13` (`index`) y `:97` (`set_residence_certificate`, usado por `show` y `download`)
- **Regla:** BR-041, BR-098, BR-151 (y BR-091/BR-092 en el borde de la descarga)
- **Qué está mal:** las tres acciones de lectura filtran por `where(household_unit: current_user.household_unit)`. Un `HouseholdUnit` es una **dirección física** que por BR-040 puede alojar varios `FamilyGroup` sin relación entre sí (el caso de los allegados, extremadamente común en Chile), y cada núcleo tiene su propio usuario con login (BR-151). El fix de aislamiento de PR #159 (`7acc76d`) cerró **solo** `selectable_residencies` y `create`; la lectura quedó igual. Consecuencias concretas para el jefe del núcleo A sobre los certificados del núcleo B que vive en la misma dirección:
  - `index`: lista folio, **nombre completo del titular**, estado, vigencia y propósito.
  - `show`: además el **`validation_code`** del certificado emitido (la llave de la verificación pública) y el monto.
  - `download`: `send_data` del PDF, que por `app/services/certificate_pdf_service.rb:91,96` contiene el **RUN completo sin enmascarar** y la **dirección completa** del titular. `downloadable?` (`app/models/residence_certificate.rb:90`) valida vigencia/titular/pago pero **no valida quién descarga**: la única barrera de pertenencia es el `household_unit`, que es justamente lo que ambos núcleos comparten.
- **Cómo lo verifiqué:** lectura del controlador (los tres puntos de scope), del `CertificatePdfService` (RUN y dirección impresos en el PDF) y de `git show 7acc76d`, cuyo diff toca únicamente `selectable_residencies`/`create` y añade dos tests que cubren solo `new` y `create`. `grep 'test "'` sobre `test/controllers/panel/residence_certificates_controller_test.rb` confirma que **ningún test cubre `index`/`show`/`download` cruzando núcleos**. En producción no hay todavía ningún `HouseholdUnit` con más de un `FamilyGroup` (consulta agregada arriba), así que la fuga no se ha producido — cierra TASK-019 del backlog en su parte de daño consumado, no en la de riesgo futuro.
- **Impacto en go-live:** **bloquea**. Es exactamente el escenario que PR #159 declaró cerrado y que la propia BR-041 declara enforced. Un vecino obtiene el PDF oficial con el RUN y el domicilio de la familia de al lado por el solo hecho de compartir dirección — y el `validation_code`, que le permite además operar la verificación pública de ese certificado. Con vecinos reales aparece el primer domicilio con dos núcleos casi de inmediato.
- **Fix sugerido:** un único scope de pertenencia reutilizado por las tres acciones, análogo a `selectable_residencies`: `ResidenceCertificate.joins(member: {verified_identity: :residencies}).where(residencies: {family_group_id: current_user.family_group_id, status: "approved"})`, o —más simple y robusto— filtrar por los `member_id` que devuelve `selectable_residencies`. Añadir tests de `index`, `show` y `download` con dos `FamilyGroup` en el mismo `HouseholdUnit` (el fixture ya se construye así en el test de `create`, líneas 368-381).

---

## Alta

### [SEVERIDAD: Alta] Cualquier admin de junta puede convertir un RUN arbitrario en el domicilio y los convivientes de otra junta
- **Archivo:** `app/controllers/admin/onboarding_reviews_controller.rb:21-43`; vista `app/views/admin/onboarding_reviews/step3.html.erb:193-199` y `:269-277`
- **Regla:** BR-007 (aislamiento multi-tenant) vs. BR-057/BR-058 (alerta informativa de RUN duplicado) — choque de reglas, resuelto hoy a favor de la divulgación
- **Qué está mal:** `step3` hace `VerifiedIdentity.find_by(run: ...)` **global, sin scope de junta**, y arma `@matching_household_units` uniendo los domicilios de esa identidad **en cualquier junta** (`identity_hu_ids`, línea 37). La vista los renderiza con todo detalle:
  - línea 193-199: nombre de **la otra junta**, nombre de la delegación, número de casa y calle del domicilio actual de esa persona;
  - línea 269-277: para cada domicilio, y explícitamente marcando los de otra junta (`unless same_association`), `hu.current_residencies.map(&:name).join(', ')` — es decir, **el nombre completo de todos los residentes de ese domicilio ajeno**, personas que nunca tuvieron relación alguna con la junta que está mirando.

  El input que dispara la consulta es el RUN, y el RUN lo controla el solicitante… pero también el admin: nada impide que un admin registre una cuenta de correo desechable, envíe a **su propia junta** un onboarding con el RUN de cualquier persona de Chile, y entre a `review/step3`. El resultado es un buscador RUN → junta + delegación + calle + número + nombres de los convivientes, operable por el titular de cualquier cuenta de admin. BR-044/BR-057 justifican **alertar** al admin de que el RUN ya está verificado; no justifican entregarle el domicilio y el padrón familiar del titular en otra junta.
- **Cómo lo verifiqué:** lectura del controlador (la consulta a `VerifiedIdentity` no tiene `where(neighborhood_association:)` ni ningún filtro; `address_matches` sí está scopeado, `identity_hu_ids` no) y de la vista, donde la rama `unless same_association` demuestra que mostrar domicilios de otras juntas es intencional en el diseño actual. No lo ejecuté contra producción: hay una sola junta, así que el escenario cross-tenant no es reproducible con los datos vivos.
- **Impacto en go-live:** **bloquea**. Es una fuga de datos entre responsables de tratamiento distintos y, peor, un mecanismo de consulta dirigida por RUN. En Chile el RUN de terceros circula con facilidad (contratos, boletas, redes sociales), así que la precondición del ataque es trivial. El daño no es de la junta emisora: es de personas que no son sus socias.
- **Fix sugerido:** separar «alertar» de «divulgar». Mantener el aviso de RUN ya verificado (un booleano y, a lo sumo, la comparación de nombre/apellido/teléfono que ya se muestra en el bloque de transición). Para los domicilios: incluir en `@matching_household_units` **solo** los de `current_neighborhood_association` (`address_matches` y los `identity_hu_ids` intersectados con la junta propia); para los ajenos, mostrar a lo sumo «esta persona tiene una membresía activa en otra junta» sin nombre de junta, sin dirección y sin lista de convivientes. La lista de `current_residencies` debe restringirse además al `FamilyGroup` pertinente, por coherencia con BR-041.

### [SEVERIDAD: Alta] RUN, nombre, teléfono y domicilio quedan en texto plano en los logs de producción
- **Archivo:** `config/initializers/filter_parameter_logging.rb:6-8`; `config/environments/production.rb:38,41`
- **Regla:** falta regla (ninguna BR cubre retención ni minimización en logs; el principio de finalidad de la ley 19.628 sí)
- **Qué está mal:** `filter_parameters` filtra `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`. **No filtra** `run`, `first_name`, `last_name`, `phone`, `street_name`, `number`, `address_detail`, `organization_rut`. `ActionController::LogSubscriber` escribe la línea `Parameters: {...}` a nivel **info**, y `config.log_level` es `info`. Cada PATCH del onboarding (que además usa autosave por Turbo, o sea muchas escrituras por sesión), cada alta manual de socio y cada registro de dependiente deja el RUN y el domicilio completos en STDOUT → `docker logs` del host, sin rotación acotada, sin cifrado y accesible a cualquiera con acceso al servidor o al recolector de logs. El `ssn` de la lista por defecto de Rails delata el hueco: es el equivalente estadounidense del RUN, y el chileno no se agregó.
- **Cómo lo verifiqué:** ejecutado en producción, solo lectura: `bin/rails runner` devolvió `filter_params: "[:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, ...]"` y `log_level: 1` (= `info`). Cruzado con `production.rb:38` (`ActiveSupport::TaggedLogging.logger(STDOUT)`).
- **Impacto en go-live:** **bloquea**. Es una copia paralela, indefinida y no gobernada de la base de datos personal, fuera de todo control de acceso de la aplicación. Hoy con 20 identidades es contenible; el día 1 con vecinos reales deja de serlo, y no es retroactivamente reparable (los logs ya escritos no se des-escriben).
- **Fix sugerido:** añadir a `filter_parameters`: `:run, :rut, :first_name, :last_name, :phone, :street_name, :number, :address_detail, :identification`. La lista es de coincidencia **parcial**, así que `:rut` cubre también `organization_rut`, pero `:run` no lo cubre (no es subcadena suya): hacen falta las dos entradas. Cuidado con `:number`, que por coincidencia parcial también filtrará `phone_number` y similares — es lo deseable aquí. Verificar después con un POST de onboarding en staging que la línea `Parameters:` muestre `[FILTERED]`. Complementariamente, fijar retención y rotación de los logs del contenedor (`--log-opt max-size/max-file` en Kamal).

### [SEVERIDAD: Alta] No existe política de privacidad ni consentimiento informado para el tratamiento de datos personales
- **Archivo:** `config/routes.rb` (no hay ruta de política ni de términos); `app/views/panel/onboarding/step4.html.erb:165-176`; `config/locales/es.yml:1034`
- **Regla:** falta regla. BR-015 exige `terms_accepted_at` pero no define qué se acepta
- **Qué está mal:** el único checkbox del flujo dice, literalmente: *«Declaro que los datos ingresados son verídicos y acepto la responsabilidad legal sobre la veracidad de esta información.»* Eso es una declaración de veracidad del titular, **no** una autorización para tratar sus datos. No hay ninguna página de política de privacidad, ni de términos, ni un aviso de qué se recolecta, con qué finalidad, por cuánto tiempo, quién lo ve (la directiva de la junta, el staff de Yuntapp) ni a quién se comunica (MercadoPago recibe nombre, apellido y RUN — ver Baja más abajo). Grepeé `privacidad|privacy|términos|terms` en vistas, locales y rutas: el único acierto sustantivo es el `privacy_note` de `panel/household_neighbours`, que es un texto de UI, no un documento.
- **Cómo lo verifiqué:** `grep -rn "privacidad\|privacy\|terminos\|términos\|terms" app/views config/locales/es.yml config/routes.rb`; lectura del checkbox de `step4` y de su traducción; `ls public/` (solo páginas de error y favicons).
- **Impacto en go-live:** **bloquea**, y es el único hallazgo que no se arregla con código. La ley 19.628 exige autorización **expresa y por escrito** del titular para tratar datos personales, e informar la finalidad. Mientras los datos eran del owner esto era irrelevante; desde el momento en que entra el primer vecino, cada onboarding es un tratamiento sin base legal documentada, y la junta de vecinos —que también es responsable— queda expuesta junto con Yuntapp.
- **Fix sugerido:** publicar una política de privacidad (ruta pública, junto a `/como-funciona`) que cubra: datos recolectados (RUN, nombre, teléfono, domicilio, imágenes de cédula y comprobantes), finalidad (verificación de residencia y emisión del certificado), destinatarios (directiva de la junta emisora, staff de Yuntapp, MercadoPago para el pago), plazo de conservación, y el canal para ejercer los derechos de acceso, rectificación y cancelación. Separar el checkbox en dos: veracidad (el actual) y autorización de tratamiento (nuevo, con enlace a la política), y persistir ambos con su timestamp y la versión del documento aceptada.

---

## Media

### [SEVERIDAD: Media] El flujo de pago comparte el mismo scope por domicilio: se puede pagar y ver el certificado de otro núcleo familiar
- **Archivo:** `app/controllers/panel/payments_controller.rb:61-63` (`set_certificate`) y `:65-71` (`find_certificate_by_external_reference`)
- **Regla:** BR-041, BR-098
- **Qué está mal:** mismo defecto que el hallazgo Crítico, en otro archivo: ambos métodos filtran por `where(household_unit: current_user.household_unit)`. El jefe del núcleo A puede abrir `new_panel_payment_path(certificate_id: <cert del núcleo B>)` y llevar a MercadoPago un pago cuyo `payer` es él mismo (`MercadopagoPayer#mercadopago_payer` toma `current_user`) para un certificado ajeno; y las páginas `success`/`failure`/`pending` le muestran el certificado del vecino con nombre y estado. Además queda un desajuste de datos: el pago lo hace una persona y el titular es otra, sin registro de esa disociación más allá de `requested_by`.
- **Cómo lo verifiqué:** lectura del controlador y del concern `MercadopagoPayer` (`app/controllers/concerns/mercadopago_payer.rb:9-16`).
- **Impacto en go-live:** no bloquea por sí solo (el daño de lectura es menor que el del PDF), pero **debe corregirse en el mismo cambio** que el hallazgo Crítico: si se arregla solo el controlador de certificados, esta ruta sigue exponiendo el nombre del titular ajeno y permitiendo pagos cruzados.
- **Fix sugerido:** reutilizar el mismo scope por `family_group` en ambos métodos.

### [SEVERIDAD: Media] Un admin puede trasladar un domicilio (con sus residentes) a la delegación de otra junta, y el formulario le lista las delegaciones de todas las juntas
- **Archivo:** `app/controllers/admin/household_units_controller.rb:73` (`household_unit_params` permite `:neighborhood_delegation_id` y `:commune_id`); `app/views/admin/household_units/_form.html.erb:5` (`NeighborhoodDelegation.all`); `app/models/household_unit.rb:4` (sin validación de pertenencia)
- **Regla:** BR-007
- **Qué está mal:** el `<select>` de delegación se puebla con `NeighborhoodDelegation.all`, o sea que el admin de la junta A ve por pantalla los nombres de las delegaciones de **todas** las juntas del país. Y como `set_household_unit` scopea la lectura pero `update` acepta cualquier `neighborhood_delegation_id`, el admin puede reasignar un domicilio propio —con sus `Residency`, es decir con las personas— a una delegación de la junta B. A partir de ese momento ese domicilio aparece en `admin/household_units` de la junta B, y sus residentes salen listados por nombre en el `step3` de cualquier revisión de onboarding de esa junta (ver hallazgo Alta anterior, línea 276). Es el mismo patrón que BR-007 ya corrigió en `BoardMember` (`member_id` por strong params con un `<select>` acotado como única defensa), pero aquí ni siquiera el `<select>` está acotado.
- **Cómo lo verifiqué:** lectura de los tres archivos. `HouseholdUnit` solo valida `presence: true` en `number`; no hay validación análoga a `BoardMember#member_belongs_to_association`.
- **Impacto en go-live:** no bloquea el lanzamiento con una sola junta en producción, pero se vuelve explotable en cuanto haya dos. Es una exfiltración deliberada, no accidental — requiere un admin malicioso o coludido.
- **Fix sugerido:** acotar el `<select>` a `current_neighborhood_association.neighborhood_delegations` y —lo que de verdad corta— añadir a `HouseholdUnit` una validación de que la delegación pertenece a la junta esperada, o resolver la delegación en el controlador desde el scope de la junta en vez de aceptarla por params.

### [SEVERIDAD: Media] `admin/members#create` sobrescribe la identidad verificada de una persona que pertenece a otra junta
- **Archivo:** `app/controllers/admin/members_controller.rb:55-58`
- **Regla:** BR-007, BR-044, BR-046, BR-012
- **Qué está mal:** el alta manual hace `VerifiedIdentity.find_or_initialize_by(run: run)` y a continuación `assign_attributes(verified_identity_params.except(:run))`. `VerifiedIdentity` es un registro **global** (RUN único en toda la plataforma, BR-012). Si el RUN que teclea el admin ya existe —porque esa persona es socia de otra junta— el `find_or_initialize_by` **la encuentra** y el `save` dentro de la transacción le reescribe `first_name`, `last_name`, `phone` y `email` con lo que haya tipeado el admin de la junta A. Esa identidad es la que alimenta el nombre impreso en los certificados ya emitidos por la junta B (`CertificatePdfService#member_full_name`) y el que muestra su verificación pública. `update` sí excluye `:run` por BR-046, pero nadie protege el resto de los campos, y `create` no comprueba si la identidad hallada tiene ya miembros en otras juntas.
- **Cómo lo verifiqué:** lectura del controlador. Contrasta con `Admin::OnboardingReviewsController#approve_step3:55-63`, que hace el mismo `find_or_initialize_by` pero **sí** invoca después `IdentityTransferService.deactivate_prior_memberships!` — es decir, el flujo de onboarding trata el RUN duplicado como una transferencia deliberada (ADR-006/BR-057-059) y el alta manual no lo trata en absoluto.
- **Impacto en go-live:** no bloquea con una junta. Con varias, un admin puede alterar el nombre con el que un vecino de otra junta figura en sus certificados oficiales, sin dejar rastro de aprobación ni verificación documental, y sin que el admin legítimo se entere.
- **Fix sugerido:** si `find_or_initialize_by` devuelve un registro persistido, **no** reasignar sus atributos: reutilizar la identidad tal cual y mostrar al admin un aviso de RUN ya verificado (con el mismo criterio de mínima divulgación del hallazgo Alta), exigiendo confirmación explícita como ya hace `Superadmin::AdministrationRequestsController#approve` con `confirm_duplicate_run`.

### [SEVERIDAD: Media] El onboarding no valida que la delegación elegida pertenezca a la junta elegida
- **Archivo:** `app/models/residence_verification_request.rb:4,16-18`; `app/controllers/panel/onboarding_controller.rb:609`
- **Regla:** BR-007, BR-016
- **Qué está mal:** `residence_verification_params` permite `:neighborhood_delegation_id` y el modelo solo valida su **presencia** (cuando no hay calle), nunca que la delegación pertenezca a `neighborhood_association`. El `<select>` sí está acotado a `@neighborhood_association.neighborhood_delegations`, pero es defensa de cliente. Con un PATCH manipulado en `step3`, un vecino envía la solicitud a la junta A declarando una delegación de la junta B; si el admin de A aprueba (la vista de revisión muestra solo el **nombre** de la delegación, sin decir de qué junta es), `approve_step3:107-126` crea el `HouseholdUnit` colgando de la delegación ajena. El domicilio y sus residentes quedan bajo el ámbito de consulta de la junta B, y el socio queda además en un estado inconsistente: `certificate_association` se resuelve por la delegación (`panel/residence_certificates_controller.rb:131`) y devolvería la junta B, donde no tiene `Member` aprobado.
- **Cómo lo verifiqué:** lectura del modelo (no hay validación cruzada), de los strong params y de la ruta de aprobación.
- **Impacto en go-live:** no bloquea; requiere manipulación deliberada del request y sobre todo requiere más de una junta. Pero es el mismo hueco estructural que el hallazgo anterior, y conviene cerrarlos juntos.
- **Fix sugerido:** validación en `ResidenceVerificationRequest` (y en `HouseholdUnit`) de que `neighborhood_delegation.neighborhood_association_id == neighborhood_association_id`. Mostrar la junta de la delegación en la vista de revisión del admin.

### [SEVERIDAD: Media] Las sesiones no expiran nunca y el login no tiene límite de intentos
- **Archivo:** `config/initializers/devise.rb:191` (`config.timeout_in` comentado), `:167` (`remember_for` comentado, `:rememberable` activo en `app/models/user.rb:5`); `config/initializers/rack_attack.rb:15-17`
- **Regla:** falta regla
- **Qué está mal:** el módulo `:timeoutable` no está habilitado y `timeout_in` está comentado, así que una sesión iniciada dura lo que dure la cookie; con `:rememberable` activo, el «recuérdame» extiende eso a las 2 semanas por defecto. Rack::Attack está correctamente montado (verifiqué el railtie de la gema, que hace `app.middleware.use`) pero **solo** limita `/verify` a 10 req/min por IP: no hay throttle en `/users/sign_in` ni en `/users/password`. Las cuentas en juego no son cuentas cualquiera: la de un admin de junta da acceso a las fotos de cédula y a los domicilios de todos sus socios.
- **Cómo lo verifiqué:** lectura del inicializador de Devise (grep de `paranoid|timeout_in|remember_for`), del inicializador de Rack::Attack, y del railtie de `rack-attack 6.8.0` para confirmar que el middleware sí se inserta.
- **Impacto en go-live:** no bloquea, pero es el control que falta entre «alguien adivina una contraseña» y «alguien descarga el padrón de una junta». También pesa el escenario del computador compartido en la sede vecinal, donde una sesión de admin sin expiración queda viva indefinidamente.
- **Fix sugerido:** habilitar `:timeoutable` con `config.timeout_in = 2.hours` (o 30 min para admin/superadmin), acotar `remember_for`, y añadir throttles de Rack::Attack por IP y por email en `POST /users/sign_in` y `POST /users/password`.

---

## Baja

### [SEVERIDAD: Baja] El `validation_code` se genera con un PRNG no criptográfico
- **Archivo:** `app/models/residence_certificate.rb:303-308`
- **Regla:** BR-074
- **Qué está mal:** `Array.new(8) { VALIDATION_CODE_ALPHABET.sample }` usa `Random::DEFAULT` (Mersenne Twister), no `SecureRandom`. El `validation_token` sí es `SecureRandom.uuid` (línea 216). El código es la llave de una página pública que revela nombre completo del titular, junta emisora, propósito y fechas.
- **Cómo lo verifiqué:** lectura del modelo; el alfabeto tiene 32 símbolos (24 letras sin O/I + 8 dígitos 2-9), o sea 32⁸ ≈ 1,1·10¹² combinaciones, y `rack_attack.rb` limita a 10 intentos/min por IP.
- **Impacto en go-live:** no bloquea. El espacio de búsqueda y el throttle hacen el ataque por fuerza bruta impracticable; la objeción es de higiene criptográfica, no de exposición demostrable.
- **Fix sugerido:** `VALIDATION_CODE_ALPHABET.sample(random: SecureRandom)` o construirlo con `SecureRandom.random_number`.

### [SEVERIDAD: Baja] Se envían nombre, apellido y RUN a MercadoPago sin base de transferencia documentada
- **Archivo:** `app/controllers/concerns/mercadopago_payer.rb:9-16`
- **Regla:** falta regla
- **Qué está mal:** cada checkout envía a MP `email`, `name`, `surname` e `identification: {type: "RUT", number: <RUN sin guión>}`. La finalidad es legítima (pre-llenado y antifraude del medio de pago) y el dato es del pagador, no de un tercero. El problema es que ninguna regla ni documento lo declara, y la política de privacidad inexistente (ver Alta) tampoco.
- **Cómo lo verifiqué:** lectura del concern y de `MercadopagoService#create_preference`, que inserta `payload[:payer]`.
- **Impacto en go-live:** no bloquea técnicamente, pero es uno de los puntos que la política de privacidad debe nombrar explícitamente para que el consentimiento sea informado.
- **Fix sugerido:** declararlo en la política de privacidad y añadir una BR de la categoría Pagos que fije qué datos personales salen hacia MP y por qué.

### [SEVERIDAD: Baja] Enumeración de cuentas por correo (Devise sin `paranoid`)
- **Archivo:** `config/initializers/devise.rb:93` (`config.paranoid` comentado)
- **Regla:** falta regla
- **Qué está mal:** con `paranoid` desactivado, el registro y la recuperación de contraseña distinguen entre «correo ya registrado» y «correo desconocido». Permite confirmar si una persona concreta es usuaria de yuntapp — que, por el producto, equivale a confirmar que es vecina de una junta. `ReactivationsController#create` sí está bien hecho (`app/controllers/reactivations_controller.rb:14-20`: responde siempre igual, y su comentario lo dice explícitamente), así que el criterio ya existe en el proyecto, solo que no se aplicó a Devise.
- **Cómo lo verifiqué:** grep del inicializador; lectura de `ReactivationsController` como contraste.
- **Impacto en go-live:** no bloquea.
- **Fix sugerido:** `config.paranoid = true`, revisando que los mensajes de `registrations#create` sigan siendo utilizables.

### [SEVERIDAD: Baja] La Content Security Policy está completamente desactivada
- **Archivo:** `config/initializers/content_security_policy.rb` (íntegramente comentado)
- **Regla:** falta regla
- **Qué está mal:** no se emite ninguna cabecera CSP. No es una fuga por sí misma, pero es la red de contención que convertiría un XSS en algo inocuo; y en `config/brakeman.ignore` hay dos avisos «XSS Weak» silenciados en `residence_certificates/new.html.erb` (revisados y descartados como falsos positivos en PR #159, correctamente). Las cabeceras por defecto de Rails 8 sí están (`X-Frame-Options`, `nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`), lo cual mitiga la fuga de las URLs firmadas de Active Storage por `Referer`.
- **Cómo lo verifiqué:** lectura del inicializador y de `config/brakeman.ignore`.
- **Impacto en go-live:** no bloquea.
- **Fix sugerido:** activar una CSP en modo `report_only` primero, dado que la app usa importmap y Turbo.

### [SEVERIDAD: Baja] `?items=all` devuelve las filas crudas de varios modelos a cualquier usuario autenticado
- **Archivo:** `app/controllers/neighborhood_associations_controller.rb:55`, `app/controllers/listings_controller.rb:64`, `app/controllers/categories_controller.rb:55`, `app/controllers/tags_controller.rb:55`
- **Regla:** BR-143 (parcialmente) — falta regla sobre qué columnas expone un endpoint JSON
- **Qué está mal:** `render json: NeighborhoodAssociation.all` (y equivalentes) serializa **todas las columnas** del modelo, no una vista curada. Para juntas eso incluye el `rut` de la organización; para `Listing.published`, `payment_id`, `payment_status`, `platform_fee`, `subscription_amount`, `preapproval_id`, `paid_at` y `user_id` de publicaciones de terceros. No hay datos personales de personas naturales ahí, pero sí metadatos financieros y de pago de otros socios, y el `user_id` permite correlacionar publicaciones con una misma persona. Nota positiva: `listings` ya usa `published_scope` en las cuatro entradas, incluido este bypass — la remediación de BR-143 quedó completa.
- **Cómo lo verifiqué:** lectura de los cuatro controladores y de las columnas en `db/schema.rb` (`listings`, `neighborhood_associations`).
- **Impacto en go-live:** no bloquea.
- **Fix sugerido:** que `disabled_pagination` renderice la misma plantilla jbuilder que el resto (`search.json.jbuilder` expone solo `value`/`text`), en lugar de `render json: <relation>`.

### [SEVERIDAD: Baja] Los documentos de identidad se sirven por rutas de Active Storage sin autorización propia, y los blobs no se purgan nunca
- **Archivo:** `config/application.rb:31`; `app/views/admin/verifications/_verified_identity.html.erb:28,30`; `app/views/admin/dependent_reviews/show.html.erb:66`; `app/views/superadmin/administration_requests/show.html.erb:89,92`
- **Regla:** BR-147 (complemento)
- **Qué está mal:** las fotos de cédula se enlazan con `rails_blob_path`/`url_for(doc)`. Verifiqué en el código de Active Storage 8.1.3.1 (`config/routes.rb:34,60`) que esas URLs firman el `signed_id` con `ActiveStorage.urls_expire_in`, y en producción ese valor es efectivamente `5 minutes` — o sea que BR-147 está bien aplicado y una URL copiada caduca. Lo que queda es que las rutas `/rails/active_storage/...` no consultan `current_user`: durante esa ventana de 5 minutos, la URL es un portador válido para cualquiera. Y ningún proceso purga los blobs: los 28 documentos ya subidos, incluidos los de solicitudes rechazadas o canceladas, se conservan indefinidamente sin plazo declarado.
- **Cómo lo verifiqué:** ejecutado en producción: `as_urls_expire: "5 minutes"`, `as_service: :local`. Lectura del código de la gema para confirmar que `urls_expire_in` alimenta el `signed_id` de `rails_blob_path` (no solo el `service_url`). `grep` de `purge` en `app/`: solo aparece en `panel/onboarding#delete_document`, borrado voluntario del propio usuario.
- **Impacto en go-live:** no bloquea; el modo `:local` mantiene los archivos en el disco del servidor, tras la app, y la firma caduca. Es defensa en profundidad y, sobre todo, un plazo de conservación que la política de privacidad tendrá que declarar.
- **Fix sugerido:** considerar `active_storage.resolve_model_to_route = :rails_storage_proxy` con un controlador propio que verifique pertenencia, y definir una política de retención (p. ej. purgar los `identity_documents` de solicitudes `rejected`/`cancelled` pasados N meses).

### [SEVERIDAD: Baja] `admin/members/:id` revienta con 500 — la vista invoca un adjunto que no existe
- **Archivo:** `app/views/admin/members/_member.html.erb:53,58`
- **Regla:** ninguna (bug adyacente, encontrado al inventariar qué datos personales muestra esa página)
- **Qué está mal:** la vista hace `member.documents.attached?` y `member.documents.each`, pero `Member` no declara ningún `has_many_attached`; los adjuntos de documentos viven en `Residency` (`app/models/residency.rb:9`), `IdentityVerificationRequest` y `VerifiedIdentity`. Toda visita a la ficha de un socio termina en `NoMethodError`.
- **Cómo lo verifiqué:** `grep has_many_attached app/models` (Member no aparece) y, para no dejarlo en inferencia, ejecutado en producción: `Member.new.respond_to?(:documents)` → `false`, `Residency.new.respond_to?(:documents)` → `true`. Además, `grep 'test "'` sobre `test/controllers/admin/members_controller_test.rb` confirma que **no hay ningún test que haga `get admin_member_url`**: por eso la suite pasa en verde.
- **Impacto en go-live:** no bloquea la privacidad, pero sí rompe la ficha de socio, que es la pantalla donde el admin consulta RUN, teléfono y correo de un vecino. Lo señalo aquí porque el mismo parche debería decidir **qué** documentos corresponde mostrar ahí y con qué scope.
- **Fix sugerido:** eliminar el bloque o apuntarlo a la fuente real (`member.verified_identity.identity_document`, o los `documents` de la `Residency` vigente), y añadir un test de `show`.

---

## Áreas revisadas y limpias

- **Verificación pública `/verify/:identifier`** — `VerificationsController` + `app/views/verifications/show.html.erb`: el RUN sale enmascarado por `masked_run`, que **falla cerrado** (`residence_certificate.rb:108-118`: un RUN fuera del formato normalizado se enmascara entero, con cuatro tests que lo cubren). No expone el domicilio. El scope `findable_publicly` impide alcanzar certificados no emitidos (BR-081), y la precedencia No válido > Vencido está bien implementada (BR-091/BR-141). Con throttle de 10 req/min por IP.
- **Vitrina del marketplace** — `/listings` requiere sesión (hereda `authenticate_user!`), consulta solo `Listing.published` en las cuatro entradas incluido el bypass `items=all`, y ni la vista ni el jbuilder exponen dato alguno del vendedor más allá de `user_id`.
- **Páginas de junta y guía** — `neighborhood_associations#show` muestra únicamente id y nombre; `panel/neighborhood_association` muestra la directiva por **nombre**, sin RUN; `home` y `guide` no consultan ningún modelo.
- **Aislamiento entre juntas en el resto de `admin/`** — `members`, `listings`, `residence_certificates`, `board_members`, `neighborhood_delegations`, `onboarding_requests`, `onboarding_reviews`, `dependent_reviews`, `verifications`, `certificate_pricings` y `listing_pricings` scopean **todas** sus consultas (incluidas `search` y el bypass `items=all`) por `current_neighborhood_association`. `BoardMember` valida en el modelo que el socio sea de la junta (BR-007, remediado). `Admin::ListingsController` excluye `:user_id` de los strong params.
- **`panel/dependents` y `panel/household_neighbours`** — filtran por `family_group` en todas sus consultas; `household_neighbours` devuelve solo recuentos agregados, sin un solo nombre (BR-041/BR-042 bien resuelto).
- **Cuentas y sesiones (BR-101)** — el hook `activatable` de Devise verifica `active_for_authentication?` en **cada** request, así que desactivar o bloquear corta la sesión viva, no solo el próximo login. `User#email_is_immutable` lleva BR-093 al modelo, cubriendo panel, admin y consola.
- **Superficie de autenticación** — solo tres controladores saltan `authenticate_user!` (`home`, `guide`, `reactivations`) y solo dos heredan de `ActionController::Base` (`verifications`, `webhooks/mercadopago`); ninguno toca datos personales identificables sin control.
- **Inyección vía `sort_scope`/`filter_scope`** — los prefijos `sort_by_`/`filter_by_` y las listas de `permit` acotan el `send` a los scopes declarados en `Sortable`/`Filterable`; la dirección de orden la valida Rails.
- **Correos** — `ResidenceCertificateMailer#issued` no incluye RUN ni domicilio; los digest al staff y las alertas de reversión tampoco.
- **HTTPS y cookies** — `force_ssl = true` verificado en producción, con HSTS y cookies `secure`; `attributes_for_inspect = [:id]` evita volcar atributos en trazas.
