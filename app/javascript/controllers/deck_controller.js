import { Controller } from "@hotwired/stimulus"

// Deck de diapositivas para la guía pública /como-funciona.
// Muestra una diapositiva a la vez y permite avanzar con botones, clic en la
// diapositiva, flechas del teclado y swipe. El Acto 2 es opcional: la
// diapositiva de bifurcación usa #goto para saltar directo al cierre.
export default class extends Controller {
  static targets = ["slide", "prev", "next", "progress"]

  connect() {
    this.index = 0
    this.touchStartX = null
    this.onKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.onKeydown)
    this.show()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
  }

  next() {
    if (this.index < this.lastIndex) {
      this.index++
      this.show()
    }
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.show()
    }
  }

  // Salto directo (bifurcación → cierre). Usa data-deck-index-param.
  goto(event) {
    const target = Number(event.params.index)
    if (!Number.isNaN(target) && target >= 0 && target <= this.lastIndex) {
      this.index = target
      this.show()
    }
  }

  reset() {
    this.index = 0
    this.show()
  }

  // Clic en la diapositiva para avanzar, salvo que el clic sea sobre un botón/enlace.
  advance(event) {
    if (event.target.closest("button, a")) return
    this.next()
  }

  touchStart(event) {
    this.touchStartX = event.changedTouches[0].screenX
  }

  touchEnd(event) {
    if (this.touchStartX === null) return
    const delta = event.changedTouches[0].screenX - this.touchStartX
    if (Math.abs(delta) > 50) {
      if (delta < 0) {
        this.next()
      } else {
        this.prev()
      }
    }
    this.touchStartX = null
  }

  handleKeydown(event) {
    if (event.key === "ArrowRight") this.next()
    if (event.key === "ArrowLeft") this.prev()
  }

  show() {
    this.slideTargets.forEach((slide, i) => {
      const active = i === this.index
      slide.classList.toggle("hidden", !active)
      slide.setAttribute("aria-hidden", active ? "false" : "true")
    })

    if (this.hasProgressTarget) {
      const pct = ((this.index + 1) / this.slideTargets.length) * 100
      this.progressTarget.style.width = `${pct}%`
    }

    if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = this.index === this.lastIndex

    const heading = this.slideTargets[this.index].querySelector("h2, h1")
    if (heading) heading.focus()
    window.scrollTo({ top: 0, behavior: "instant" })
  }

  get lastIndex() {
    return this.slideTargets.length - 1
  }
}
