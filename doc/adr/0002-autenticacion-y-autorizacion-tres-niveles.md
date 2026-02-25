# ADR-0002: Autenticacion y autorizacion con tres niveles de acceso

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

La plataforma tiene tres tipos de usuarios con distintos permisos: superadministradores del sistema, administradores de juntas de vecinos, y usuarios/socios regulares. Se necesita un sistema de autenticacion robusto con control de acceso por rol.

## Decision

- **Autenticacion**: Devise (database_authenticatable, registerable, recoverable, rememberable, validatable).
- **Autorizacion**: Control de acceso por roles con flags booleanos (`superadmin`, `admin`) en el modelo User, verificados en before_actions de los controladores base de cada namespace.
- **Tres niveles**:
  - `Superadmin::ApplicationController` → verifica `ensure_superadmin!`
  - `Admin::ApplicationController` → verifica `ensure_neighborhood_admin!` (superadmin o admin con asociacion)
  - `Panel` → requiere solo `authenticate_user!`
- **Impersonacion**: Superadmin puede impersonar asociaciones via `session[:impersonated_neighborhood_association_id]` para administrarlas sin credenciales separadas.
- **Redireccion post-login**: `after_sign_in_path_for` redirige segun rol (superadmin → superadmin_root, admin → admin_root, usuario → panel_root).

## Alternativas consideradas

- **Pundit/CanCanCan**: Mas granular pero agrega complejidad innecesaria para tres roles fijos.
- **JWT stateless**: No es idomiatico en Rails con vistas server-rendered.
- **Roles en tabla separada**: Sobre-ingenieria para un sistema con roles fijos.

## Consecuencias

- Simple y predecible. Los roles son booleanos, no hay tabla de roles ni polimorfismo.
- Si en el futuro se necesitan permisos mas granulares (ej: roles parciales de admin), habria que migrar a Pundit o similar.
- La impersonacion por sesion es efectiva pero no deja audit trail automatico.
