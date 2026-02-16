import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectGroup", "inputGroup", "select", "input", "checkbox"]

  connect() {
    // Al conectar NO ejecutamos toggle() directamente si no es necesario,
    // o lo hacemos sin disparar eventos para evitar bucle al cargar la página
    
    // Verificamos si hay un valor en el input manual al iniciar
    // Si manual_address es true O si hay algo escrito en address_line_1, activamos modo manual visualmente
    // PERO respetamos el estado del checkbox si ya viene renderizado checked por Rails
    
    // El checkbox ya debería venir con 'checked' si el modelo tiene manual_address: true
    // Así que solo necesitamos refrescar la visibilidad basada en ese estado.
    this.refreshVisibility()
  }

  toggle(event) {
    // Si viene de un evento de cambio real del checkbox, disparamos limpieza
    const isManual = this.checkboxTarget.checked
    this.refreshVisibility()
    
    // Disparamos evento en el checkbox para que autosave lo detecte y guarde el booleano
    // Autosave escucha 'change' en el formulario o inputs. Como este es un evento 'change' nativo
    // del checkbox, si el controlador autosave está en el formulario padre, lo capturará.
    // Pero si el checkbox está fuera o autosave requiere acción específica, lo forzamos.
    // El checkbox ya tiene data-action="change->manual-address#toggle", si agregamos autosave, bien.
    // Pero mejor dejar que el evento burbujee o disparar submit en el form si es necesario.
    // En este caso, el checkbox es parte del form que tiene data-controller="autosave".
    
    if (isManual) {
      // Limpiamos el select y disparamos cambio
      if (this.selectTarget.value !== "") {
          this.selectTarget.value = ""
          this.selectTarget.dispatchEvent(new Event("change")) 
      }
    } else {
      // Limpiamos el input manual y disparamos input
      if (this.inputTarget.value !== "") {
          this.inputTarget.value = ""
          this.inputTarget.dispatchEvent(new Event("input"))
      }
    }
    
    // Forzamos autosave del checkbox mismo si no se disparó por los otros campos
    this.checkboxTarget.form.requestSubmit()
  }

  refreshVisibility() {
    const isManual = this.checkboxTarget.checked

    if (isManual) {
      this.selectGroupTarget.classList.add("hidden")
      this.inputGroupTarget.classList.remove("hidden")
      this.selectTarget.removeAttribute("required")
      this.inputTarget.setAttribute("required", "required")
    } else {
      this.selectGroupTarget.classList.remove("hidden")
      this.inputGroupTarget.classList.add("hidden")
      this.inputTarget.removeAttribute("required")
      this.selectTarget.setAttribute("required", "required")
    }
  }
}