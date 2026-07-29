# Guía pública "Cómo funciona" — Diseño

**Fecha:** 2026-07-29
**Estado:** Aprobado (diseño)
**Autor:** Claude Code (brainstorming con el owner)

## Objetivo

Crear una presentación accesible **desde la web sin necesidad de loguear** que explique el
sistema Yuntapp de forma muy simple, pensada para **una persona que le cuesta entender un
sistema**. Debe cubrir tanto el flujo principal del producto (solicitar/pagar/descargar/verificar
un certificado de residencia) como el modelo de dominio por detrás, en **dos niveles**: un
recorrido simple obligatorio y una profundización opcional.

## Decisiones tomadas (brainstorming)

- **Entrega:** ruta pública dentro de la app Rails (no archivo autónomo).
- **Ruta:** `GET /como-funciona`.
- **Formato:** diapositivas (deck), una idea por pantalla.
- **Alcance:** dominio + flujo, en dos niveles.
- **Estilo:** cálido y cercano (lenguaje muy simple, analogías, íconos grandes, colores amables).
- **Acto 2 opcional:** al terminar el flujo simple, el lector decide si quiere ver "cómo funciona
  por dentro" o ir directo al cierre.
- **Enfoque técnico:** Stimulus controller propio (`deck_controller`), sin dependencias nuevas.
  Descartado Reveal.js (dependencia pesada) y JS inline (rompe convención del repo).

## Arquitectura

### Ruta y controlador

```ruby
# config/routes.rb (junto al resto de rutas públicas: home, verify)
get "como-funciona", to: "guide#index", as: :guide
```

```ruby
# app/controllers/guide_controller.rb
class GuideController < ApplicationController
  skip_before_action :authenticate_user!   # público, igual que HomeController
  layout "guide"

  def index; end
end
```

Precedentes en el repo: `HomeController` usa `skip_before_action :authenticate_user!`;
`VerificationsController` usa un layout autónomo (`verification.html.erb`). Seguimos ambos patrones.

### Layout

Nuevo `app/views/layouts/guide.html.erb`: autónomo y minimalista (sin el navbar de la app para no
distraer), con Tailwind ya disponible vía `tailwindcss-rails`. Incluye `<meta viewport>` para móvil,
`javascript_importmap_tags` y el theme claro.

### Vista y parciales

- `app/views/guide/index.html.erb`: contenedor del deck + navegación.
- Cada diapositiva es un parcial en `app/views/guide/slides/` (una idea por archivo), para mantener
  el contenido legible y editable. El texto en español va **inline en los parciales**, no en
  `es.yml`: es prosa larga tipo landing, solo-español, y meterla en i18n la haría ilegible. Decisión
  consciente, documentada aquí.

### Stimulus controller

`app/javascript/controllers/deck_controller.js`:
- Targets: `slide` (cada diapositiva), `progress` (barra/indicador), `counter` ("Paso N de M"),
  botones `prev`/`next`.
- Estado: índice de diapositiva actual.
- Acciones: `next`, `prev`, `goto(index)`, `reset`.
- Entradas: clic en cualquier parte del área de contenido para avanzar, flechas ←/→ del teclado,
  swipe táctil en móvil.
- Muestra solo la diapositiva activa (las demás `hidden` + `aria-hidden`).
- Respeta `prefers-reduced-motion` (sin transiciones si el usuario lo pide).

## Estructura del deck (contenido)

### Acto 1 · La historia de María (nivel simple, obligatorio)

1. **¿Qué es Yuntapp?** — una frase: "Saca tu certificado de residencia por internet, sin ir a la
   municipalidad."
2. **Conoce a María** — una vecina cualquiera que necesita su certificado.
3. **María crea su cuenta** — como abrir un correo (email + clave).
4. **Se hace socia de su junta** — muestra quién es (carnet) y dónde vive; la junta lo revisa
   **una sola vez** (onboarding).
5. **Pide su certificado** — elige para qué lo necesita.
6. **Paga en línea** — con MercadoPago, desde el celular.
7. **Lo recibe al instante** — el sistema lo emite solo y ella lo descarga en PDF.
8. **Cualquiera puede comprobar que es real** — con el QR, un código o un link (verificación
   pública).
9. **Bifurcación** — "¿Quieres ver cómo funciona por dentro?" → [Sí, muéstrame] · [Con esto me
   basta → pantalla final].

### Acto 2 · Cómo funciona por dentro (opcional, "para saber más")

Cada concepto con una analogía cotidiana:

10. **La idea clave** — el sistema separa tres cosas que en la vida real son distintas:
    **quién eres** / **dónde vives** / **tu vínculo con la junta**.
11. **La cuenta (User)** — tu llave de entrada. Se puede desactivar, nunca se borra.
12. **Tu identidad (VerifiedIdentity)** — tu carnet, anclado al RUN (te identifica aunque cambies
    de cuenta).
13. **Tu membresía (Member)** — tu carné de socio de esa junta. Nunca se borra; si te vas, queda
    inactivo con tu historial.
14. **Tu casa y tu familia (HouseholdUnit + FamilyGroup)** — una dirección puede tener varias
    familias; hay personas (adultos mayores, niños) que registra alguien por ellas (dependientes).
15. **La junta (NeighborhoodAssociation)** — quien emite el certificado; necesita RUT para ser
    legal.
16. **El certificado (ResidenceCertificate)** — sus estados y por qué **el pago va primero**
    (nunca se emite sin pago confirmado).
17. **Directiva y marketplace (BoardMember + Listing)** — breve: quién dirige la junta y las
    publicaciones vecinales.
18. **Nada se borra** — todo queda como historial (principio de integridad).
19. **Cierre + mini-mapa** — recap visual y "volver al inicio".

## Navegación (pensada para quien le cuesta)

- Botones grandes **Atrás / Siguiente** siempre visibles.
- Clic en cualquier parte del contenido para avanzar.
- Flechas ←/→ del teclado.
- Swipe en móvil.
- Barra de progreso + contador "Paso N de M".
- Botón "Volver al inicio".
- Sin gestos ocultos ni jerga técnica.

## Estilo

- Tailwind (ya disponible), paleta cálida (ámbar / verde suave), tipografía grande, mucho aire.
- Un ícono/emoji grande por diapositiva, una idea por pantalla, frases cortas.
- Accesibilidad: alto contraste, foco visible, ARIA en la navegación (`role`, `aria-live` en el
  contador, `aria-hidden` en diapositivas ocultas), respeto a `prefers-reduced-motion`.

## Testing

Test de request mínimo (`test/controllers/guide_controller_test.rb`):

- `GET /como-funciona` responde **200 sin usuario logueado** (el requisito crítico del pedido).
- La respuesta contiene los hitos del deck (p. ej. título de la portada y marcadores de ambos actos).

## Fuera de alcance (YAGNI)

- Sin backend dinámico ni datos reales: el deck es contenido estático explicativo.
- Sin i18n multi-idioma (solo español).
- Sin analítica ni tracking.
- Sin edición desde admin (el contenido se cambia editando los parciales).
```