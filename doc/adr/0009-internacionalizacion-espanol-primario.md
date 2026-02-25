# ADR-0009: Internacionalizacion con espanol como idioma primario

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

La plataforma esta dirigida a juntas de vecinos chilenas. La interfaz debe estar en espanol.

## Decision

- **Idioma primario**: Espanol (`es.yml`).
- **Fallback**: Ingles (`en.yml`) habilitado en produccion (`config.i18n.fallbacks = true`).
- **Todas las cadenas de texto** en vistas usan `I18n.t()` para labels, flash messages, titulos y botones.
- **Devise** tiene locale propio (`devise.en.yml`) con traducciones de formularios de autenticacion.
- **ActiveRecord**: Nombres de modelos y atributos traducidos en `activerecord.models` y `activerecord.attributes`.
- **Fechas y horas**: Ver ADR-0001.
- **Validaciones custom**: Mensajes de error en espanol definidos en `activerecord.errors.models`.

## Alternativas consideradas

- **Solo ingles**: No sirve para el mercado objetivo.
- **Sin i18n (strings hardcodeadas)**: Inmantenible y no escalable.
- **Multiples idiomas completos**: Innecesario por ahora, pero la infraestructura i18n lo permite a futuro.

## Consecuencias

- Toda la interfaz esta en espanol consistente.
- Agregar otro idioma requiere solo crear un nuevo archivo de locale y traducir.
- El fallback a ingles previene errores de "translation missing" en produccion para keys no traducidas.
