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

  # --- Production parity: build de la imagen de producción y tests DENTRO
  # del contenedor. Atrapa gaps entre el entorno local y producción (versión
  # de Ruby, gemas nativas, librerías de sistema como libvips) ANTES del deploy.
  step "Docker: build imagen de producción", "docker build --platform linux/amd64 -t yuntapp-ci ."
  # --tmpfs /rails/coverage: el contenedor corre como uid 1000 y /rails es de root;
  # SimpleCov necesita un directorio de cobertura escribible o falla en at_exit.
  step "Tests: dentro del contenedor", "docker run --rm -e RAILS_ENV=test --tmpfs /rails/coverage:uid=1000 yuntapp-ci bin/rails db:test:prepare test"

  # --- Signoff: el gate de merge y deploy ---
  if success?
    step "Signoff: listo para merge y deploy.", "gh signoff"
  else
    failure "Signoff: el CI falló. No mergear ni desplegar.", "Corrige los pasos de arriba y corre bin/ci de nuevo."
  end
end
