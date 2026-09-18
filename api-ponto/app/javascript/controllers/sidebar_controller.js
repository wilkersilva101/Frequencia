import { Controller } from "@hotwired/stimulus"

// Não existe app/javascript/controllers/sidebar_controller.js no basic8 (diretório
// app/javascript/controllers/ do basic8 só tem application_controller.js, hello_controller.js,
// index.js e theme_controller.js — confirmado lendo o diretório completo e via
// `git log --all -- '*sidebar*'`, que não retorna nenhum arquivo desse nome). O basic8 delega o
// toggle da sidebar inteiramente ao JS nativo do AdminLTE 4 (atributo `data-lte-toggle="sidebar"`,
// classe `sidebar-collapse` no <body>, persistência própria em localStorage — ver
// node_modules/admin-lte/dist/js/adminlte.js, classe SidebarToggle, STORAGE_KEY_SIDEBAR_STATE).
//
// O Frequencia, antes desta task, já tinha essa mesma persistência reimplementada como <script>
// inline em app/views/layouts/admin.html.erb (chave "admin-sidebar-collapsed"). É essa lógica
// inline — a fonte real e já existente no próprio Frequencia, não uma invenção — que foi portada
// aqui para Stimulus, seguindo o mesmo padrão arquitetural do theme_controller.js (task 24.7).
//
// O <script> inline foi mantido de propósito (remoção é escopo da task 25.5, conforme a nota da
// Sprint 24) — não há conflito funcional real entre os dois: ambos usam a mesma chave de
// localStorage e a mesma semântica (espelhar a classe `sidebar-collapse` do <body> para o
// localStorage e reaplicá-la no load), então a duplicação é redundante mas não quebra nada.
export default class extends Controller {
  static values = {
    key: { type: String, default: "admin-sidebar-collapsed" }
  }

  connect() {
    this.applyStored()
    this._onTurboLoad = () => this.applyStored()
    document.addEventListener("turbo:load", this._onTurboLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this._onTurboLoad)
  }

  // O AdminLTE nativo já alterna a classe `sidebar-collapse` no <body> ao clicar no elemento
  // [data-lte-toggle="sidebar"] (mesmo elemento que carrega este controller). Aqui só
  // persistimos o estado resultante, com um pequeno delay para rodar depois do listener nativo
  // do AdminLTE ter aplicado a classe (mesma técnica usada no <script> inline original).
  toggle() {
    setTimeout(() => this.save(), 300)
  }

  applyStored() {
    if (this.getPreferred()) {
      document.body.classList.add("sidebar-collapse")
    } else {
      document.body.classList.remove("sidebar-collapse")
    }
  }

  save() {
    const isCollapsed = document.body.classList.contains("sidebar-collapse")
    localStorage.setItem(this.keyValue, isCollapsed)
  }

  getPreferred() {
    return localStorage.getItem(this.keyValue) === "true"
  }
}
