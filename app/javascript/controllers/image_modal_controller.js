import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image", "counter"]
  static values = { urls: Array }

  open(event) {
    this.currentIndex = Number(event.currentTarget.dataset.index)
    this.show()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  next(event) {
    event.stopPropagation()
    if (this.urlsValue.length <= 1) return
    this.currentIndex = (this.currentIndex + 1) % this.urlsValue.length
    this.show()
  }

  prev(event) {
    event.stopPropagation()
    if (this.urlsValue.length <= 1) return
    this.currentIndex = (this.currentIndex - 1 + this.urlsValue.length) % this.urlsValue.length
    this.show()
  }

  keydown(event) {
    if (event.key === "ArrowRight") this.next(event)
    else if (event.key === "ArrowLeft") this.prev(event)
  }

  show() {
    this.imageTarget.src = this.urlsValue[this.currentIndex]
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.currentIndex + 1} / ${this.urlsValue.length}`
    }
  }
}
