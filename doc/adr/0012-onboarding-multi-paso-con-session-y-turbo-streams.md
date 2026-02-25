# ADR-0012: Onboarding multi-paso con session state y Turbo Streams

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

El flujo principal de la aplicacion es el onboarding de un usuario para convertirse en socio de una junta de vecinos. Requiere 4 pasos: seleccion de asociacion, verificacion de identidad (con documentos), verificacion de residencia (con comprobantes), y confirmacion.

## Decision

- **4 pasos secuenciales** con rutas GET (mostrar) y PATCH (actualizar) por paso.
- **Session state**: `session[:onboarding]` almacena IDs de onboarding_request, identity_request, residence_request y neighborhood_association para mantener estado entre requests.
- **Persistencia inmediata**: Cada modelo se crea en estado `draft` al entrar al paso. Los campos se guardan con autosave (PATCH parcial) sin esperar al submit final.
- **Before actions de guardia**: `ensure_step1!`, `ensure_step2!`, `ensure_step3!`, `ensure_step4!` impiden saltar pasos.
- **`ensure_draft!`**: Bloquea modificaciones cuando la solicitud ya fue enviada (status != draft).
- **Turbo Streams**: Cada campo tiene su propio turbo_frame y partial. Al hacer autosave, el servidor responde con `turbo_stream.replace` del campo validado y del boton de submit.
- **Documentos**: Upload via Active Storage con `has_many_attached`. Se adjuntan con `.attach()` separado de `assign_attributes` para evitar duplicacion.
- **Step 4 (confirmacion)**: Muestra resumen read-only con miniaturas de documentos y modal de visualizacion.
- **Submit final**: Cambia status de onboarding_request, identity_verification_request y residence_verification_request a `pending`. Limpia la session.

## Alternativas consideradas

- **Wizard JavaScript** (ej: multi-step form en frontend): Mas logica en el cliente, dificil de validar server-side, estado se pierde si se cierra el navegador.
- **Un solo formulario largo**: Mala UX para un proceso de 4 pasos con uploads.
- **API-first con SPA**: Complejidad innecesaria para formularios server-rendered.

## Consecuencias

- El servidor es la fuente de verdad en todo momento. No hay estado solo en el cliente.
- El usuario puede cerrar el navegador y retomar donde quedo (datos persistidos en draft).
- Requiere un partial por campo para que Turbo Streams funcione (mas archivos, pero cada uno es simple).
- La session se limpia al enviar, evitando datos stale.
