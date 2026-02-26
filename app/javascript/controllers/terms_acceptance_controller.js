import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "submit"]

  connect() {
    this.toggle()
    this.submitTargets.forEach(el => {
      if (el.tagName === "A") {
        el.addEventListener("click", this._preventIfDisabled)
      }
    })
  }

  disconnect() {
    this.submitTargets.forEach(el => {
      if (el.tagName === "A") {
        el.removeEventListener("click", this._preventIfDisabled)
      }
    })
  }

  toggle() {
    const checked = this.checkboxTarget.checked

    this.submitTargets.forEach(el => {
      if (el.tagName === "A") {
        el.setAttribute("aria-disabled", !checked)
        el.classList.toggle("btn-disabled", !checked)
      } else {
        el.disabled = !checked
      }
    })
  }

  _preventIfDisabled = (event) => {
    if (event.currentTarget.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
    }
  }
}
