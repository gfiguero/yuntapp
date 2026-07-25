import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Hace una fila de tabla completa clickeable, navegando a la URL indicada.
// Los links y botones internos de la fila conservan su comportamiento propio.
export default class extends Controller {
  static values = { url: String }

  visit(event) {
    if (event.target.closest("a, button")) return

    Turbo.visit(this.urlValue)
  }
}
