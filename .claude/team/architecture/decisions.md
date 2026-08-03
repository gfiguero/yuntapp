# Architecture Decision Records (ADRs)

> **Los ADRs se movieron a [`doc/adr/`](../../../doc/adr/README.md).**
>
> Hasta el 2026-08-02 este archivo mantenía su propia numeración (`ADR-001`–`ADR-006`), que **colisionaba** con la de `doc/adr/` (`0001`–`0013`): había dos "ADR-005" distintos, dos "ADR-003" distintos, y así. Se unificaron en `doc/adr/`, que ya tenía el formato completo y más decisiones documentadas.

## Dónde quedó cada uno

| Antes (aquí) | Ahora |
|--------------|-------|
| ADR-001 · Autenticación con Devise | [0002 · Autenticación y autorización con tres niveles](../../../doc/adr/0002-autenticacion-y-autorizacion-tres-niveles.md) |
| ADR-002 · Frontend con Hotwire | [0004 · Frontend con Hotwire, Tailwind y DaisyUI](../../../doc/adr/0004-frontend-hotwire-tailwind-daisyui.md) |
| ADR-003 · SQLite3 como base de datos | [0005 · SQLite como base de datos](../../../doc/adr/0005-sqlite-como-base-de-datos.md) y [0008 · Solid Cache/Queue/Cable](../../../doc/adr/0008-solid-cache-queue-cable.md) |
| ADR-004 · Asset Pipeline con Propshaft + Importmap | [0003 · Asset pipeline con Importmap + Propshaft](../../../doc/adr/0003-asset-pipeline-importmap-propshaft.md) |
| ADR-005 · Deploy con Kamal + Docker | [0007 · Deploy con Kamal, Docker y Thruster](../../../doc/adr/0007-deploy-kamal-docker-thruster.md) |
| ADR-006 · Servicio compartido de RUN duplicado | [0014 · Detección de RUN duplicado y transferencia de identidad](../../../doc/adr/0014-transferencia-de-identidad-por-run-duplicado.md) |

Las alternativas y consecuencias que solo estaban documentadas aquí (Rodauth y autenticación desde cero en el 0002; ViewComponent en el 0004; la dependencia de la rama `main` de Devise) se fusionaron en los ADRs de destino. Nada se perdió.

## Para agregar una decisión nueva

Crea un archivo en `doc/adr/` siguiendo las instrucciones de su [README](../../../doc/adr/README.md). No agregues ADRs a este archivo.
