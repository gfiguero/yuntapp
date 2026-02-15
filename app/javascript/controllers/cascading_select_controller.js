import { Controller } from "@hotwired/stimulus"

// Cascading select controller for Region → Commune → NeighborhoodAssociation.
// Embeds full data tree as a JSON value to avoid extra API requests.
//
// Data format:
//   [{ id, name, communes: [{ id, name, associations: [{ id, name }] }] }]
//
export default class extends Controller {
  static targets = ["region", "commune", "association", "output"]
  static values  = { data: Array }

  connect() {
    this.populateRegions()
  }

  populateRegions() {
    this.clearSelect(this.regionTarget, this.regionTarget.dataset.prompt)
    this.dataValue.forEach(region => {
      this.regionTarget.add(new Option(region.name, region.id))
    })

    this.clearSelect(this.communeTarget, this.communeTarget.dataset.prompt)
    this.communeTarget.disabled = true

    this.clearSelect(this.associationTarget, this.associationTarget.dataset.prompt)
    this.associationTarget.disabled = true

    this.outputTarget.value = ""
  }

  regionChanged() {
    const regionId = parseInt(this.regionTarget.value)
    const region = this.dataValue.find(r => r.id === regionId)
    const communes = region ? region.communes : []

    this.clearSelect(this.communeTarget, this.communeTarget.dataset.prompt)
    communes.forEach(c => {
      this.communeTarget.add(new Option(c.name, c.id))
    })
    this.communeTarget.disabled = communes.length === 0

    this.clearSelect(this.associationTarget, this.associationTarget.dataset.prompt)
    this.associationTarget.disabled = true

    this.outputTarget.value = ""
  }

  communeChanged() {
    const regionId  = parseInt(this.regionTarget.value)
    const communeId = parseInt(this.communeTarget.value)

    const region  = this.dataValue.find(r => r.id === regionId)
    const commune = region ? region.communes.find(c => c.id === communeId) : null
    const associations = commune ? commune.associations : []

    this.clearSelect(this.associationTarget, this.associationTarget.dataset.prompt)
    associations.forEach(a => {
      this.associationTarget.add(new Option(a.name, a.id))
    })
    this.associationTarget.disabled = associations.length === 0

    this.outputTarget.value = ""
  }

  associationChanged() {
    this.outputTarget.value = this.associationTarget.value
  }

  // -- helpers --

  clearSelect(select, prompt) {
    select.innerHTML = ""
    if (prompt) {
      select.add(new Option(prompt, ""))
    }
  }
}
