import { Controller } from "@hotwired/stimulus"

// Cascada región→comuna→junta con datos embebidos como JSON, más toggle a "crear nueva junta".
export default class extends Controller {
  static targets = ["region", "commune", "association", "newToggle", "existingWrap", "newWrap", "communeNew"]
  static values = { data: Array }

  connect() { this.populateRegions() }

  populateRegions() {
    this.fill(this.regionTarget, this.dataValue.map(r => [r.name, r.id]))
    this.regionChanged()
  }

  regionChanged() {
    const region = this.dataValue.find(r => r.id === parseInt(this.regionTarget.value))
    const communes = region ? region.communes : []
    this.fill(this.communeTarget, communes.map(c => [c.name, c.id]))
    if (this.hasCommuneNewTarget) this.fill(this.communeNewTarget, communes.map(c => [c.name, c.id]))
    this.communeChanged()
  }

  communeChanged() {
    const region = this.dataValue.find(r => r.id === parseInt(this.regionTarget.value))
    const commune = region ? region.communes.find(c => c.id === parseInt(this.communeTarget.value)) : null
    const associations = commune ? commune.associations : []
    this.fill(this.associationTarget, associations.map(a => [a.name, a.id]))
  }

  toggleNew() {
    const isNew = this.newToggleTarget.checked
    this.existingWrapTarget.classList.toggle("hidden", isNew)
    this.newWrapTarget.classList.toggle("hidden", !isNew)
  }

  fill(select, pairs) {
    const prompt = select.dataset.prompt || ""
    select.innerHTML = ""
    if (prompt) select.add(new Option(prompt, ""))
    pairs.forEach(([label, value]) => select.add(new Option(label, value)))
  }
}
