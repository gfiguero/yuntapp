# Folio estructurado del certificado de residencia — Diseño

**Fecha:** 2026-08-20
**Rama:** `worktree-feat-folio-estructurado`

## Problema

El folio actual es `CR-{association_id}-{sequence}` (ej. `CR-2-14`). Tiene dos defectos:

**1. No comunica nada.** Leyendo `CR-2-14` no se sabe de cuándo es el certificado. El año importa
porque la vigencia es de 30 días (BR-023): un folio de 2024 es obviamente inválido, pero el formato
actual obliga a consultar el sistema para saberlo. Los documentos oficiales chilenos reinician su
correlativo cada año justamente por eso.

**2. El correlativo se calcula parseando strings.** `next_folio` trae todos los folios de la junta,
les quita el prefijo con `delete_prefix`, convierte a entero y saca el máximo:

```ruby
def next_folio
  prefix = "CR-#{neighborhood_association_id}-"
  last = self.class
    .where(neighborhood_association_id: neighborhood_association_id)
    .where.not(folio: nil)
    .pluck(:folio)
    .map { |f| f.to_s.delete_prefix(prefix).to_i }
    .max || 0
  "#{prefix}#{last + 1}"
end
```

Es frágil (cualquier folio con formato inesperado se convierte en `0` silenciosamente vía `to_i`),
carga todos los folios en memoria, y acopla el cálculo del correlativo al formato de presentación:
cambiar el formato obliga a reescribir la asignación.

## Solución

Separar **el dato** (año + correlativo, en columnas enteras) de **su presentación** (el folio como
cadena derivada), y enriquecer el formato con el año de emisión.

```
CR-2026-0002-00015
│  │    │    └── correlativo de la junta en ese año, 5 dígitos con padding
│  │    └─────── junta emisora, 4 dígitos con padding
│  └──────────── año de emisión
└─────────────── tipo de documento (certificado de residencia)
```

**Sin dígito verificador**, por decisión del owner: el canal de verificación telefónica es el
`validation_code` (BR-074), no el folio.

## Alcance de lo que NO cambia

- `validation_token` (UUID del QR) y `validation_code` (8 chars) siguen igual. El folio **no** es el
  identificador de verificación pública.
- La verificación pública (`/verify/:identifier`) no se toca.
- El layout del PDF no cambia: solo el texto del folio que ya imprime.
- La vigencia (BR-023, 30 días) no cambia.

## Cambios

### 1. Modelo de datos

Migración con dos columnas nuevas en `residence_certificates`:

| Columna | Tipo | Null | Motivo |
|---|---|---|---|
| `folio_year` | integer | sí | Año de emisión. Nulo mientras el certificado no está emitido |
| `folio_sequence` | integer | sí | Correlativo dentro de (junta, año). Nulo mientras no está emitido |

Índice único parcial sobre `(neighborhood_association_id, folio_year, folio_sequence)` con
`WHERE folio_sequence IS NOT NULL`. Mismo patrón que los índices únicos parciales que ya existen en el
schema (#108): evita que las filas no emitidas —todas con `NULL`— compitan por el índice.

Se conserva el índice único existente sobre `(neighborhood_association_id, folio)`.

### 2. Backfill de los certificados ya emitidos

Los folios existentes **no se reescriben**: BR-008 los declara inmutables y `CR-2-7` seguirá siendo
`CR-2-7` para siempre. Lo que se puebla son las columnas nuevas, para que el correlativo continúe donde
iba:

- `folio_year` = año de `issue_date`
- `folio_sequence` = el número que ya llevaba el folio viejo, extraído con
  `folio.split("-").last.to_i`

En producción hoy hay 7 certificados emitidos, todos de 2026, con secuencias 7, 8, 10, 11, 12, 13 y 14.
Tras el backfill, el próximo folio de esa junta será `CR-2026-0002-00015`.

Un certificado emitido en un año anterior quedaría con su año real, y el correlativo del año nuevo
partiría de 1. Los formatos conviven sin colisionar porque son cadenas distintas.

### 3. Asignación del correlativo

`next_folio_sequence` reemplaza el parseo por una consulta agregada sobre la columna entera:

```ruby
def next_folio_sequence(year)
  max = self.class
    .where(neighborhood_association_id: neighborhood_association_id, folio_year: year)
    .maximum(:folio_sequence) || 0
  max + 1
end
```

Y el folio se construye a partir de los datos:

```ruby
FOLIO_PREFIX = "CR"

def build_folio(year, sequence)
  format("%s-%04d-%04d-%05d", FOLIO_PREFIX, year, neighborhood_association_id, sequence)
end
```

`issue!` asigna las tres cosas en la misma transacción que ya usa. El año sale de `issue_date`, que se
fija en esa misma asignación, así que un certificado emitido el 31 de diciembre lleva el año de su
emisión y no el del intento anterior.

### 4. Colisión y reintento

El reintento de `issue!` ante colisión de folio (#98, `FOLIO_MAX_ATTEMPTS`) se conserva íntegro. Dos
emisiones concurrentes calculan el mismo `MAX+1`, la segunda choca contra el índice único y
recalcula.

`folio_collision?` debe reconocer también el índice nuevo: hoy identifica la colisión por el nombre del
índice `index_residence_certificates_on_association_and_folio` y por el mensaje de la validación de
unicidad. Se agrega el nombre del índice nuevo a esa detección. Sin esto, una colisión de correlativo
se propagaría como error en vez de reintentarse.

Al reintentar hay que limpiar **las tres** asignaciones (`folio`, `folio_year`, `folio_sequence`), no
solo el folio.

### 5. Búsqueda

`filter_by_folio` usa `LIKE %valor%`, así que sirve para ambos formatos sin cambios. Buscar `14`
encuentra tanto `CR-2-14` como `CR-2026-0002-00014`; buscar `CR-2026` encuentra solo los nuevos.

### 6. Reglas de negocio

**BR-006 se reescribe.** Hoy dice que el formato `CR-{association_id}-{sequence}` "no puede cambiar".
La regla nueva declara el formato nuevo, deja constancia de que los certificados emitidos antes
conservan el suyo (BR-008), y explica que el correlativo vive en columnas y el folio es su
representación.

## Riesgos y decisiones

**Dos formatos conviviendo, para siempre.** Es consecuencia directa de BR-008. La alternativa
—reescribir los folios viejos— rompería la inmutabilidad del documento oficial y dejaría PDFs ya
descargados citando un folio que la plataforma ya no reconoce. Se asume la convivencia.

**El backfill parsea los folios viejos una única vez.** Es el mismo parseo frágil que queremos
eliminar, pero acotado a una migración que corre una vez sobre datos conocidos, no a la ruta de
emisión. Si un folio viejo tuviera formato inesperado, `to_i` daría `0` y el correlativo del año
arrancaría mal; por eso la migración registra en el log cada fila que backfillea, para poder revisarlo.

**El padding es cosmético.** Cuatro dígitos de junta y cinco de correlativo alcanzan para 9.999 juntas
y 99.999 certificados por junta y año. Superarlo no rompe nada: `format` no trunca, solo deja de
alinear.

**No se agrega dígito verificador.** Decisión del owner. Si más adelante se quiere validación de
transcripción, el lugar correcto es el `validation_code`, que es el que la gente dicta por teléfono.
