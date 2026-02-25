# ADR-0003: Asset pipeline con Importmap y Propshaft

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Se requiere una estrategia para servir JavaScript, CSS y otros assets. Rails 8 ofrece multiples opciones: Importmap + Propshaft (nativo), esbuild, webpack, Vite.

## Decision

- **JavaScript**: Importmap sin bundler. Las dependencias se pinean directamente en `config/importmap.rb`.
- **Assets**: Propshaft como asset pipeline (reemplazo de Sprockets).
- **CSS**: Tailwind CSS via `tailwindcss-rails` gem con compilacion nativa (sin Node.js).
- **No hay Node.js** en el proyecto. Ni `package.json`, ni `node_modules`, ni bundler JS.

## Alternativas consideradas

- **Webpack/esbuild**: Mas potente para apps con mucho JS, pero agrega Node.js como dependencia y complejidad de build.
- **Vite**: Moderno pero menos integrado con Rails en 2025.
- **Sprockets**: Legado, reemplazado por Propshaft en Rails 8.

## Consecuencias

- Builds mas rapidos y simples. No hay paso de compilacion JS.
- Despliegue mas liviano (sin Node.js en Docker).
- Si se necesitaran dependencias npm complejas (ej: chart libraries con tree-shaking), habria que migrar a esbuild.
