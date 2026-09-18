import { Controller } from "@hotwired/stimulus"

// Porta fiel do theme_controller.js do basic8 (mesma lógica de toggle
// claro/escuro/automático e persistência em localStorage). Único ajuste
// de mecanismo: aqui o registro é automático via eagerLoadControllersFrom
// (importmap-rails + stimulus-loading, ver controllers/index.js) — não há
// bundler esbuild nem application.register() manual, então nenhuma mudança
// de API do controller em si foi necessária.
export default class extends Controller {
  static targets = ["icon"]
  static values = {
    key: { type: String, default: "color-mode" }
  }

  connect() {
    this.apply(this.getPreferred())
    this._onTurboLoad = () => this.apply(this.getPreferred())
    document.addEventListener("turbo:load", this._onTurboLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this._onTurboLoad)
    this._stopAuto()
  }

  pick(event) {
    const mode = event.params.mode
    this.apply(mode)
    localStorage.setItem(this.keyValue, mode)
  }

  apply(mode) {
    let theme
    if (mode === "auto") {
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      theme = prefersDark ? "dark" : "light"
      document.documentElement.setAttribute("data-bs-theme", theme)
      this._watchAuto()
    } else {
      theme = mode
      document.documentElement.setAttribute("data-bs-theme", mode)
      this._stopAuto()
    }
    this._updateIcon(mode)
    this._syncDropdowns(theme)
  }

  getPreferred() {
    const saved = localStorage.getItem(this.keyValue)
    if (saved) return saved
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  _watchAuto() {
    this._stopAuto()
    this._mq = window.matchMedia("(prefers-color-scheme: dark)")
    this._mqListener = (e) => {
      const theme = e.matches ? "dark" : "light"
      document.documentElement.setAttribute("data-bs-theme", theme)
      this._syncDropdowns(theme)
    }
    this._mq.addEventListener("change", this._mqListener)
  }

  _stopAuto() {
    if (this._mq && this._mqListener) {
      this._mq.removeEventListener("change", this._mqListener)
    }
    this._mq = null
    this._mqListener = null
  }

  _updateIcon(mode) {
    const icons = { light: "fa-sun", dark: "fa-moon", auto: "fa-circle-half-stroke" }
    this.iconTargets.forEach((el) => { el.className = `fas ${icons[mode] || icons.light}` })
  }

  _syncDropdowns(theme) {
    this.element.querySelectorAll(".app-header .dropdown-menu, .login-page-theme .dropdown-menu")
      .forEach((menu) => { menu.setAttribute("data-bs-theme", theme) })
  }
}
