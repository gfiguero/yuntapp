import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "loading"]

  upload() {
    const files = this.inputTarget.files
    if (!files || files.length === 0) return

    // Show loading indicator
    this.loadingTarget.classList.remove("hidden")

    // Submit form immediately (no autosave delay)
    this.element.requestSubmit()

    // Disable input after submit collects form data
    this.inputTarget.disabled = true
  }
}
