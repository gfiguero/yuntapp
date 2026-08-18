# Run using bin/ci
#
# ESTE es nuestro CI. No hay servidor de CI: .github/workflows/ci.yml fue eliminado.
# Corres los checks en tu máquina y `gh signoff` pone un commit status verde
# `signoff` en el commit actual — el único status requerido en master.
# Sin signoff, no hay merge ni deploy.
#
# Requiere: gh CLI + extensión basecamp/gh-signoff, y Docker corriendo.

CI.run do
  step "Setup", "bin/setup --skip-server"

  # --- Estilo (local, rápido) ---
  step "Style: Ruby", "bin/standardrb"
  step "Style: ERB", "bundle exec erb_lint --lint-all"

  # --- Seguridad (local, rápido) ---
  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: Importmap audit", "bin/importmap audit"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager"

  # --- Autoload / boot ---
  step "Autoload: zeitwerk", "bin/rails zeitwerk:check"

  # --- Tests locales (rápidos, fallan temprano antes del build Docker) ---
  step "Tests: Rails (local)", "bin/rails test"

  # `bin/rails test` NO incluye los system tests: Rails los excluye por defecto y
  # hay que invocarlos aparte. Esta pasada usa el Chrome del host y sirve para
  # fallar temprano, antes del build Docker.
  step "Tests: system (local, Chrome del host)", "bin/rails test:system"

  # --- Production parity: build de la imagen de producción y tests DENTRO
  # del contenedor. Atrapa gaps entre el entorno local y producción (versión
  # de Ruby, gemas nativas, librerías de sistema como libvips) ANTES del deploy.
  step "Docker: build imagen de producción", "docker build --platform linux/amd64 -t yuntapp-ci ."
  # --tmpfs /rails/coverage: el contenedor corre como uid 1000 y /rails es de root;
  # SimpleCov necesita un directorio de cobertura escribible o falla en at_exit.
  step "Tests: dentro del contenedor", "docker run --rm -e RAILS_ENV=test --tmpfs /rails/coverage:uid=1000 yuntapp-ci bin/rails db:test:prepare test"

  # Los system tests contra la imagen de producción: la app corre en el artefacto
  # que se despliega y el navegador vive en un contenedor aparte. Es el único
  # paso que ejercita el JS y el CSS PRECOMPILADOS — verificado que
  # `asset_path("application.js")` resuelve al mismo digest que en producción.
  # Un importmap que no resuelve o un Tailwind que purgó una clase usada
  # dinámicamente solo se ven aquí. SKIP_BUILD: la imagen ya se construyó arriba.
  step "Tests: system (imagen de producción)", "SKIP_BUILD=1 bin/system-tests-docker"

  # --- Signoff: el gate de merge y deploy ---
  if success?
    step "Signoff: listo para merge y deploy.", "gh signoff"
  else
    failure "Signoff: el CI falló. No mergear ni desplegar.", "Corrige los pasos de arriba y corre bin/ci de nuevo."
  end
end
