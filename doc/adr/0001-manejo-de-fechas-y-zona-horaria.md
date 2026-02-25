# ADR-0001: Manejo de fechas, zona horaria y formato de visualizacion

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Yuntapp es una plataforma orientada a juntas de vecinos chilenas. Todas las operaciones relevantes (solicitudes, certificados, aprobaciones) requieren fechas y horas consistentes para los usuarios finales en Chile.

Se detectaron los siguientes problemas:

1. `config.time_zone` estaba comentado, por lo que Rails usaba UTC por defecto. Las fechas mostradas al usuario no correspondian a la hora local chilena.
2. Las vistas usaban `.strftime("%d/%m/%Y")` hardcodeado en lugar del helper de internacionalizacion `l()`, lo que generaba inconsistencia y duplicacion.
3. Faltaban las traducciones de nombres de meses y dias en el locale `es.yml`, causando errores de tipo "translation missing".

## Decision

### Almacenamiento (ISO 8601)

- La base de datos almacena todas las fechas y horas en **UTC**, que es el comportamiento por defecto de Rails y SQLite.
- Esto cumple con **ISO 8601** para el intercambio y persistencia de datos.
- No se almacenan offsets ni zonas horarias en la base de datos; la conversion se hace en la capa de aplicacion.

### Zona horaria de aplicacion

- Se configura `config.time_zone = "Santiago"` en `config/application.rb`.
- Rails convierte automaticamente de UTC (DB) a CLT/CLST (vista) y viceversa.
- `Time.zone.now`, `Time.current` y los atributos de ActiveRecord respetan esta configuracion.

### Visualizacion (locale es.yml)

- Todas las fechas en vistas usan el helper `l()` (alias de `I18n.localize`), nunca `.strftime` directo.
- Los formatos se centralizan en `config/locales/es.yml`:
  - `date.formats.default`: `%d/%m/%Y` (ej: 24/02/2026)
  - `date.formats.short`: `%d de %b` (ej: 24 de feb)
  - `date.formats.long`: `%d de %B de %Y` (ej: 24 de febrero de 2026)
  - `time.formats.short`: `%d de %b %H:%M` (ej: 24 de feb 20:15)
  - `time.formats.long`: `%d de %B de %Y %H:%M` (ej: 24 de febrero de 2026 20:15)
- Los nombres de meses y dias estan definidos en espanol en el locale.

### Convenciones de uso en vistas

| Caso | Codigo |
|------|--------|
| Solo fecha | `l(objeto.created_at.to_date)` |
| Fecha corta | `l(objeto.created_at, format: :short)` |
| Fecha larga | `l(objeto.created_at, format: :long)` |
| Fecha con hora | `l(objeto.created_at)` |

## Consecuencias

- **Positivas**: Un unico punto de cambio para formatos de fecha. Consistencia en toda la interfaz. Hora local correcta para usuarios chilenos. Almacenamiento en UTC facilita futuras necesidades de multi-zona.
- **Negativas**: Si en el futuro se necesita soportar multiples zonas horarias por usuario, se debera implementar `Time.use_zone` por request. Por ahora no es necesario dado que la app opera exclusivamente en Chile.

## Referencias

- [ISO 8601 - Date and time format](https://www.iso.org/iso-8601-date-and-time-format.html)
- [Rails Time Zone Configuration](https://api.rubyonrails.org/classes/ActiveSupport/TimeZone.html)
- [Rails I18n Localize](https://guides.rubyonrails.org/i18n.html#adding-date-time-formats)
