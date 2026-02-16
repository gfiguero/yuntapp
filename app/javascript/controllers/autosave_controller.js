import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 2000 } }

  connect() {
    console.log("Autosave controller connected")
  }

  submit(event) {
    // Resetear clases de validación inmediatamente al escribir
    // Pero SOLO si es un evento de input/change, no de blur u otros
    if (event && (event.type === "input" || event.type === "change")) {
      event.target.classList.remove("input-success", "input-error")
      // Marcamos el campo como "dirty" (modificado) para evitar que scripts externos (como validaciones HTML5 nativas o Turbo restoration)
      // re-apliquen estilos antiguos hasta que llegue la respuesta del servidor.
      event.target.dataset.dirty = "true"
    }

    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      console.log("Submitting form due to autosave...")
      this.element.requestSubmit()
    }, this.delayValue)
  }
}
