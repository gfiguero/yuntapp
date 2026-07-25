# Punto único de transferencia de identidad por RUN duplicado (ADR-006).
#
# Cuando una identidad verificada se "materializa" de nuevo —al aprobar un onboarding
# cuyo RUN ya tenía una membresía activa (BR-029/BR-057-059/BR-069) o al registrar a esa
# persona como residente dependiente de otro grupo familiar (BR-095)— las membresías
# aprobadas previas de esa misma identidad deben desactivarse en el mismo acto de aprobación.
#
# `Member#deactivate!` se encarga del resto del invariante:
#   - cascada a los residentes dependientes del socio anterior (BR-096/BR-099), y
#   - invalidación de sus certificados al quedar el `Member` en `inactive` (BR-091/BR-097).
#
# IMPORTANTE: debe invocarse ANTES de crear la nueva `Residency`/`Member`. La cascada de
# `deactivate!` resuelve el `household_admin` del socio anterior por su residencia aprobada
# más reciente; una residencia nueva de la misma identidad la confundiría.
class IdentityTransferService
  def self.deactivate_prior_memberships!(verified_identity, reason:)
    return if verified_identity.blank? || !verified_identity.persisted?

    verified_identity.members.approved.find_each do |member|
      member.deactivate!(reason: reason)
    end
  end
end
