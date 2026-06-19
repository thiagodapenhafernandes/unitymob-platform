import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-drop da árvore de hierarquia (/admin/admin_users/hierarchy).
// Cada [data-hierarchy-list] (UL) vira uma lista Sortable do mesmo grupo, permitindo:
//  - reordenar irmãos dentro da mesma lista;
//  - mover um nó para dentro de outro (re-parent => muda manager_id);
//  - soltar na lista raiz (data-manager-id vazio) para tirar da hierarquia.
// Ao soltar, persiste via PATCH move_hierarchy. O backend bloqueia ciclos; se recusar, recarrega.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortables = []
    this.element.querySelectorAll("[data-hierarchy-list]").forEach((list) => {
      this.sortables.push(this.buildSortable(list))
    })
  }

  disconnect() {
    ;(this.sortables || []).forEach((s) => s.destroy())
    this.sortables = []
  }

  buildSortable(list) {
    return Sortable.create(list, {
      group: "admin-hierarchy",
      handle: ".hier-row__handle",
      draggable: "[data-hierarchy-node]",
      animation: 150,
      fallbackOnBody: true,
      swapThreshold: 0.6,
      emptyInsertThreshold: 10,
      ghostClass: "hier-ghost",
      chosenClass: "hier-chosen",
      dragClass: "hier-drag",
      onStart: () => this.element.classList.add("is-dragging"),
      onMove: (evt) => this.allowMove(evt),
      onEnd: (evt) => {
        this.element.classList.remove("is-dragging")
        this.persist(evt)
      },
    })
  }

  // Impede soltar um nó dentro da própria subárvore (criaria ciclo).
  allowMove(evt) {
    return !evt.dragged.contains(evt.to)
  }

  persist(evt) {
    const node = evt.item
    const userId = node.dataset.userId
    const destList = evt.to
    const managerId = destList.dataset.managerId || ""
    const siblingIds = Array.from(destList.children)
      .filter((c) => c.matches && c.matches("[data-hierarchy-node]"))
      .map((c) => c.dataset.userId)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken,
      },
      body: JSON.stringify({ id: userId, manager_id: managerId, sibling_ids: siblingIds }),
    })
      .then((resp) => resp.json().then((data) => ({ ok: resp.ok, data })))
      .then(({ ok, data }) => {
        if (!ok || !data || !data.ok) {
          window.alert((data && data.error) || "Não foi possível mover. A página será recarregada.")
          window.location.reload()
        }
      })
      .catch(() => window.location.reload())
  }

  get csrfToken() {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }
}
