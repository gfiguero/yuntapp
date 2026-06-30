import { Controller } from "@hotwired/stimulus"

// Autodismiss de alertas flash después de un retardo (default 5s).
// Respeta prefers-reduced-motion: con motion reducida desaparece sin transición.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss(event) {
    if (event) event.preventDefault()
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.element.remove()
      return
    }
    this.element.style.transition = "opacity 200ms ease-out"
    this.element.style.opacity = "0"
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}
