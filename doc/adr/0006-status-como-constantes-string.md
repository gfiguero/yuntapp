# ADR-0006: Status como constantes string en vez de Rails enums

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Multiples modelos (OnboardingRequest, Member, ResidenceCertificate, VerifiedIdentity, etc.) tienen un campo `status` con valores finitos. Rails ofrece `enum` como mecanismo built-in.

## Decision

- Status definidos como constantes string: `STATUSES = %w[pending approved rejected].freeze`
- Validacion con `validates :status, inclusion: { in: STATUSES }`
- Metodos predicado manuales: `def approved? = status == "approved"`
- Scopes manuales: `scope :pending, -> { where(status: "pending") }`
- La columna en la DB almacena el string directamente (no enteros).

## Alternativas consideradas

- **Rails `enum`**: Genera automaticamente scopes, predicados y bang methods. Pero almacena enteros en la DB (menos legible) y los bang methods (`approved!`) pueden causar updates accidentales.
- **State machine gems** (AASM, Statesman): Mas formales pero sobre-ingenieria para flujos simples.

## Consecuencias

- Los valores en la DB son legibles directamente (`"pending"` vs `0`).
- Explicitud total: cada scope y predicado esta definido manualmente, sin magia.
- Mas codigo boilerplate por modelo, pero predecible y facil de buscar en el codebase.
- Concerns Filterable y Sortable generan scopes dinamicos (`filter_by_status`, `sort_by_status`) que funcionan directamente con strings.
