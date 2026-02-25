# ADR-0004: Frontend con Hotwire (Turbo + Stimulus) + Tailwind CSS + DaisyUI

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

La aplicacion necesita interactividad en formularios (autosave, selects en cascada, upload de archivos, validacion en tiempo real) sin la complejidad de un SPA.

## Decision

- **Turbo**: Turbo Drive para navegacion sin recargas. Turbo Frames para actualizaciones parciales. Turbo Streams para respuestas del servidor que actualizan campos individuales.
- **Stimulus**: Controladores ligeros para comportamiento especifico:
  - `autosave_controller`: Auto-envia formularios tras delay configurable (2s).
  - `cascading_select_controller`: Selects en cascada con datos JSON embebidos (sin API calls).
  - `manual_address_controller`: Toggle entre selector de delegacion e input manual.
  - `file_upload_controller`: Upload con loading state.
  - `image_modal_controller`: Modal de imagenes con navegacion por flechas.
  - `terms_acceptance_controller`: Habilitar/deshabilitar boton segun checkbox.
- **CSS**: Tailwind CSS utility-first + DaisyUI como libreria de componentes (drawer, alerts, badges, modals, tables).
- **Tema fijo**: `data-theme="light"` en todos los layouts.

## Alternativas consideradas

- **React/Vue SPA**: Complejidad innecesaria, requiere API separada.
- **Alpine.js**: Demasiado simple para cascading selects y autosave con Turbo Streams.
- **Bootstrap**: Menos flexible que Tailwind, mas pesado.

## Consecuencias

- Experiencia SPA-like con servidor como fuente de verdad.
- Minimo JavaScript custom (~100 lineas entre todos los controllers).
- El patron de autosave con Turbo Streams es potente pero requiere un partial por campo.
