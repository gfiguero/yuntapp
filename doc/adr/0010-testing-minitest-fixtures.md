# ADR-0010: Testing con Minitest y fixtures

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Se necesita una estrategia de testing que sea rapida, simple y consistente con el enfoque Rails-idomiatico del proyecto.

## Decision

- **Minitest** como framework de testing (default de Rails).
- **Fixtures YAML** para datos de prueba (`test/fixtures/*.yml`), cargados globalmente con `fixtures :all`.
- **SimpleCov** para reportes de cobertura de codigo.
- **Capybara + Selenium** disponibles para system tests (aunque el foco actual es en tests de modelos y controladores).
- Tests ejecutados con `bin/rails test`.

## Alternativas consideradas

- **RSpec**: Mas expresivo pero agrega dependencia y configuracion. Minitest es mas simple y nativo.
- **FactoryBot**: Mas flexible que fixtures para datos complejos, pero fixtures son mas rapidos (cargados una vez en transaccion).
- **Parallel tests**: Comentado en `test_helper.rb`. SQLite tiene limitaciones con acceso concurrente.

## Consecuencias

- Tests rapidos gracias a fixtures transaccionales.
- Fixtures requieren mantenimiento manual cuando cambian los modelos.
- Sin paralelizacion por limitaciones de SQLite.
