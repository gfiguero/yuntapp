# ADR-0015: System tests por caso de uso, con production parity

## Estado

Aceptado — 2026-08-18

## Fecha

2026-08-18

## Contexto

La propuesta inicial fue **un caso de uso por cada regla de negocio, y un system test por cada uno**.
Son 132 reglas vigentes. Medido sobre este codebase, eso daba ~20 minutos de CI, y buena parte de las
reglas no es observable desde un navegador:

- **Integridad** (15 reglas): transaccionalidad, cascadas, guards `before_destroy`.
- **Pagos** (15): dependen de webhooks de MercadoPago — servidor a servidor, sin UI.
- **Normalización** (3): callbacks del modelo.
- **Multi-tenant** (5): el vector real es un POST manipulado, no un click. El IDOR de directiva
  (Batch J, J2) se caza con un request forjado; un system test solo hace lo que la UI permite.

Al mismo tiempo, la app concentra lógica **en el cliente** que ningún controller test alcanza: selects
en cascada por Turbo Stream, `autosave_controller` con debounce, `administration_cascade_controller`
que puebla selects vacíos desde JSON, `terms_acceptance_controller`. Todo eso estaba sin cobertura.

Se pilotó UC-002 para medir antes de decidir (PR #157).

## Decisión

**Un system test por caso de uso (UC-XXX), no por regla de negocio.** Las reglas se prueban en el
nivel que les corresponde: modelo para invariantes y normalización, controller para autorización y
multi-tenant, job/mailer para lo asíncrono.

Los system tests corren en **dos modos, misma suite**:

| Modo | Cómo | Qué cubre |
|---|---|---|
| Local | `bin/rails test:system` | Ciclo de desarrollo. Chrome del host, arranque rápido |
| Producción | `bin/system-tests-docker` | La app en la imagen desplegable + Chrome en contenedor aparte |

El modo producción es el único que ejercita **los assets precompilados**. Se verificó que
`asset_path("application.js")` resuelve al mismo digest en `RAILS_ENV=test` dentro del contenedor que
en producción, así que un importmap que no resuelve, un controller de Stimulus que `pin_all_from` no
recoge o una clase que Tailwind purgó solo se detectan ahí.

**Chrome nunca va dentro de la imagen de producción.** Eso la haría dejar de ser el artefacto que se
despliega, que es justamente lo que se quiere probar, además de sumarle ~500MB y superficie de ataque.

## Alternativas consideradas

- **Un system test por regla de negocio (la propuesta original)**: ~20 min de CI y ~40% de las reglas
  no verificables desde un navegador. Además un UC atraviesa varias reglas de una pasada: el test de
  UC-002 cubre BR-013, BR-015, BR-017, BR-019 y BR-020 en un solo arranque de Chrome.
- **Chrome dentro de la imagen de producción**: parity falsa, imagen inflada, navegador en lo desplegado.
- **Un stage `test` en el Dockerfile que herede de la imagen final y añada Chrome**: da casi la misma
  cobertura que la solución adoptada, pero la imagen bajo prueba deja de ser byte a byte la desplegable.
- **Solo modo local**: se pierde la única verificación de assets precompilados que existe.

## Consecuencias

- Los UC-004 (pago) y UC-005 (emisión automática) **no tienen system test** y no deben tenerlo: su
  núcleo es un webhook y un job, sin UI. Se cubren en controller y job tests.
- UC-006 cubre la navegación hasta el enlace de descarga, no la descarga binaria: verificar el archivo
  en disco exigiría configurar el directorio de descargas de Chrome, más flakiness que valor. El
  `send_data` ya está cubierto en el controller test.
- Costo real medido: **7 system tests en 14.3s** en local. El arranque de Chrome se amortiza entre
  tests del mismo run, así que el costo marginal por test es bajo (~1.5s), no los ~10s del primero.
- `config/ci.rb` gana dos pasos: uno local que falla temprano y uno contra la imagen de producción
  después del build.
- **Los system tests esperan señales de la UI, nunca `sleep`.** Con Turbo el submit es asíncrono:
  consultar la base justo después de un `click_button` lee una transacción que todavía no cerró. La
  señal correcta es el flash, la navegación, o que un botón deshabilitado se habilite.
- `parallelize` sigue comentado en `test_helper.rb:46`. Con esta cantidad no molesta; si la suite
  creciera, conviene averiguar por qué se desactivó antes de sumar más system tests.
