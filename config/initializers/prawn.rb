require "prawn"

# Prawn's built-in AFM fonts have limited UTF-8 support. Suprimimos el warning
# global; el CertificatePdfService configura fuentes adecuadas cuando renderiza.
Prawn::Fonts::AFM.hide_m17n_warning = true
