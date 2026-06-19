import { Controller } from "@hotwired/stimulus"
// Universal Attribute Manager
// Connects a "Manage" button to ax-modal CRUD operations on AttributeOptions
export default class extends Controller {
  static values = {
    context: String,
    category: String,
    fieldName: String, // e.g. "habitation[caracteristicas][]"
    modalId: { type: String, default: "attributeManagerModal" }
  }

  connect() {
    const modalElement = document.getElementById(this.modalIdValue)
    if (!modalElement) {
      console.error("AttributeManager: modal indisponível", { modalId: this.modalIdValue })
      return
    }

    if (modalElement.parentElement !== document.body) {
      document.body.appendChild(modalElement)
    }

    this.modalElement = modalElement
    this.boundModalSubmit = this.handleModalSubmit.bind(this)
    this.boundModalClick = this.handleModalClick.bind(this)
    modalElement.addEventListener("submit", this.boundModalSubmit)
    modalElement.addEventListener("click", this.boundModalClick)
  }

  disconnect() {
    if (!this.modalElement) return

    this.modalElement.removeEventListener("submit", this.boundModalSubmit)
    this.modalElement.removeEventListener("click", this.boundModalClick)
  }

  handleModalSubmit(event) {
    const editForm = event.target.closest("[data-attribute-manager-edit-form]")
    if (editForm) {
      this.update(event)
      return
    }

    if (!event.target.closest("[data-attribute-manager-form]")) return

    this.create(event)
  }

  handleModalClick(event) {
    const cancelEditButton = event.target.closest("[data-attribute-manager-action='cancel-edit']")
    if (cancelEditButton) {
      event.preventDefault()
      event.stopPropagation()
      this.cancelInlineEdit()
      return
    }

    const cancelDeleteButton = event.target.closest("[data-attribute-manager-action='cancel-delete']")
    if (cancelDeleteButton) {
      event.preventDefault()
      event.stopPropagation()
      this.cancelDeleteConfirmation(cancelDeleteButton)
      return
    }

    const editButton = event.target.closest("[data-attribute-manager-action='edit']")
    if (editButton) {
      event.preventDefault()
      event.stopPropagation()
      this.startEdit({ currentTarget: editButton })
      return
    }

    const deleteButton = event.target.closest("[data-attribute-manager-action='delete']")
    if (deleteButton) {
      event.preventDefault()
      event.stopPropagation()
      this.delete({ currentTarget: deleteButton })
    }
  }

  // Action: open ax-modal and fetch data
  open(event) {
    event.preventDefault()

    const btn = event.currentTarget
    this.contextValue = btn.dataset.attributeManagerContextValue
    this.categoryValue = btn.dataset.attributeManagerCategoryValue
    this.fieldNameValue = btn.dataset.attributeManagerFieldNameValue
    this.targetSelectId = btn.dataset.selectId
    this.element.dataset.attributeManagerContextValue = this.contextValue
    this.element.dataset.attributeManagerCategoryValue = this.categoryValue

    if (!this.contextValue || !this.categoryValue) {
      console.error("AttributeManager: contexto/categoria não definidos para este gerenciador.")
      return
    }
    if (!this.modalElement) {
      console.error("AttributeManager: modal indisponível no momento.")
      return
    }

    this.clearMessage()
    this.fetchAttributes()
    this.modalElement.dispatchEvent(new CustomEvent("ax-modal:open", { bubbles: true }))

    const title = btn.dataset.title || "Gerenciar Atributos"
    document.getElementById(`${this.modalIdValue}Title`).textContent = title
  }

  async fetchAttributes() {
    const listContainer = document.getElementById(`${this.modalIdValue}List`)
    listContainer.innerHTML = '<div class="ax-attribute-modal__state"><span class="ax-attribute-modal__spinner" role="status" aria-label="Carregando"></span></div>'
    listContainer.scrollTop = 0

    try {
      const url = `/admin/attribute_options.json?context=${encodeURIComponent(this.contextValue)}&category=${encodeURIComponent(this.categoryValue)}`
      const response = await fetch(url, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const contentType = response.headers.get("content-type") || ""
      if (!contentType.includes("application/json")) throw new Error(`Conteudo inesperado: ${contentType}`)
      const data = await response.json()
      if (!Array.isArray(data)) throw new Error("Resposta JSON inválida para listagem")
      this.renderList(data)
    } catch (error) {
      console.error("Erro ao buscar atributos:", error)
      listContainer.innerHTML = '<p class="ax-attribute-modal__state ax-attribute-modal__state--danger">Erro ao carregar opções.</p>'
    }
  }

  renderList(attributes) {
    const listContainer = document.getElementById(`${this.modalIdValue}List`)

    if (attributes.length === 0) {
      listContainer.innerHTML = '<p class="ax-attribute-modal__state">Nenhum atributo cadastrado.</p>'
      return
    }

    let html = '<ul class="ax-attribute-list">'
    attributes.forEach(attr => {
      const escapedName = this.escapeHtml(attr.name)
      html += `
        <li class="ax-attribute-list__item" data-attribute-manager-item data-id="${attr.id}" data-name="${escapedName}">
          <span class="ax-attribute-list__label" title="${escapedName}">${escapedName}</span>
          <div class="ax-attribute-list__actions">
            <button type="button" class="ax-attribute-list__action"
                    data-attribute-manager-action="edit"
                    data-id="${attr.id}"
                    data-name="${escapedName}"
                    title="Renomear">
              <i class="bi bi-pencil"></i>
            </button>
            <button type="button" class="ax-attribute-list__action ax-attribute-list__action--danger"
                    data-attribute-manager-action="delete"
                    data-id="${attr.id}"
                    data-name="${escapedName}"
                    title="Excluir">
              <i class="bi bi-trash"></i>
            </button>
          </div>
        </li>
      `
    })
    html += '</ul>'
    listContainer.innerHTML = html
    listContainer.scrollTop = 0
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;")
  }

  messageElement() {
    return document.getElementById(`${this.modalIdValue}Message`)
  }

  showMessage(message, type = "info") {
    const element = this.messageElement()
    if (!element) return

    element.textContent = message
    element.hidden = false
    element.className = `ax-attribute-modal__message ax-attribute-modal__message--${type}`
  }

  clearMessage() {
    const element = this.messageElement()
    if (!element) return

    element.textContent = ""
    element.hidden = true
    element.className = "ax-attribute-modal__message"
  }

  // Action: Create New Attribute
  async create(event) {
    event.preventDefault()
    this.clearMessage()
    const input = document.getElementById(`${this.modalIdValue}Input`)
    const name = input.value.trim()
    const context = this.contextValue || this.element.dataset.attributeManagerContextValue
    const category = this.categoryValue || this.element.dataset.attributeManagerCategoryValue

    if (!name) return
    if (!context || !category) {
      this.showMessage("Não foi possível identificar o contexto. Feche e abra o gerenciador novamente.", "danger")
      return
    }

    const btn = event.submitter || event.currentTarget.querySelector('button[type="submit"]')
    const originalText = btn.innerHTML
    btn.disabled = true
    btn.innerHTML = '<span class="ax-attribute-modal__spinner ax-attribute-modal__spinner--button" role="status"></span>'

    try {
      const response = await fetch('/admin/attribute_options.json', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        credentials: 'same-origin',
        body: JSON.stringify({
          attribute_option: { name: name, category: category, context: context }
        })
      })

      if (response.ok) {
        const newAttr = await response.json()
        console.log("Attribute created successfully:", newAttr)
        input.value = ''

        // 1. Update the background select/checkbox list
        this.appendOptionToUI(newAttr)

        // 2. Refresh the modal list immediately
        this.fetchAttributes()
        this.showMessage("Opção criada e selecionada.", "success")
      } else {
        let errorData = null
        try {
          errorData = await response.json()
        } catch (_e) {
          errorData = null
        }
        console.error("Server error:", response.status, errorData)
        this.showMessage(errorData?.name ? `Erro: ${errorData.name.join(", ")}` : `Erro ao salvar (HTTP ${response.status}).`, "danger")
      }
    } catch (error) {
      console.error("Connection error:", error)
      this.showMessage("Erro de conexão. Verifique o console do navegador.", "danger")
    } finally {
      btn.disabled = false
      btn.innerHTML = originalText
    }
  }

  // Action: Delete Attribute
  async delete(event) {
    const btn = event.currentTarget
    if (btn.dataset.confirmed !== "true") {
      this.showDeleteConfirmation(btn)
      return
    }

    this.clearMessage()
    const id = btn.dataset.id
    const name = btn.dataset.name
    btn.disabled = true

    try {
      const response = await fetch(`/admin/attribute_options/${id}.json`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        credentials: 'same-origin'
      })

      if (response.ok) {
        this.fetchAttributes()
        this.removeOptionFromUI(name)
        this.showMessage("Opção removida da lista.", "success")
      } else {
        this.showMessage("Erro ao excluir.", "danger")
      }
    } catch (error) {
      console.error("Error deleting attribute:", error)
      this.showMessage("Erro de conexão ao excluir atributo.", "danger")
    } finally {
      btn.disabled = false
    }
  }

  showDeleteConfirmation(button) {
    this.clearMessage()
    this.clearDeleteConfirmations()
    const item = button.closest("[data-attribute-manager-item]")
    if (!item) return

    item.classList.add("is-confirming")
    item.insertAdjacentHTML("beforeend", `
      <div class="ax-attribute-list__confirm">
        <span>Excluir esta opção da lista?</span>
        <div class="ax-attribute-list__confirm-actions">
          <button type="button" class="ax-attribute-list__mini-btn" data-attribute-manager-action="cancel-delete">Cancelar</button>
          <button type="button"
                  class="ax-attribute-list__mini-btn ax-attribute-list__mini-btn--danger"
                  data-attribute-manager-action="delete"
                  data-confirmed="true"
                  data-id="${button.dataset.id}"
                  data-name="${this.escapeHtml(button.dataset.name)}">
            Excluir
          </button>
        </div>
      </div>
    `)
  }

  clearDeleteConfirmations() {
    this.modalElement?.querySelectorAll(".ax-attribute-list__item.is-confirming").forEach((item) => {
      item.classList.remove("is-confirming")
      item.querySelector(".ax-attribute-list__confirm")?.remove()
    })
  }

  cancelDeleteConfirmation(button) {
    const item = button.closest("[data-attribute-manager-item]")
    if (!item) return

    item.classList.remove("is-confirming")
    item.querySelector(".ax-attribute-list__confirm")?.remove()
  }

  startEdit(event) {
    this.clearMessage()
    this.clearDeleteConfirmations()
    const btn = event.currentTarget
    const id = btn.dataset.id
    const oldName = btn.dataset.name
    const item = btn.closest("[data-attribute-manager-item]")
    if (!item) return
    const escapedOldName = this.escapeHtml(oldName)

    item.classList.add("is-editing")
    item.innerHTML = `
      <form class="ax-attribute-list__edit" data-attribute-manager-edit-form data-id="${id}" data-old-name="${escapedOldName}">
        <input class="ax-attribute-list__edit-input" type="text" value="${escapedOldName}" aria-label="Nome do atributo" required>
        <div class="ax-attribute-list__edit-actions">
          <button type="submit" class="ax-attribute-list__mini-btn ax-attribute-list__mini-btn--primary">Salvar</button>
          <button type="button" class="ax-attribute-list__mini-btn" data-attribute-manager-action="cancel-edit">Cancelar</button>
        </div>
      </form>
    `

    const input = item.querySelector(".ax-attribute-list__edit-input")
    input?.focus()
    input?.select()
  }

  cancelInlineEdit() {
    this.fetchAttributes()
  }

  async update(event) {
    event.preventDefault()
    this.clearMessage()
    const form = event.target.closest("[data-attribute-manager-edit-form]")
    const input = form?.querySelector(".ax-attribute-list__edit-input")
    const id = form?.dataset.id
    const oldName = form?.dataset.oldName
    const newName = input?.value || ""
    const trimmed = newName.trim()
    if (!trimmed || trimmed === oldName) return
    const context = this.contextValue || this.element.dataset.attributeManagerContextValue
    const category = this.categoryValue || this.element.dataset.attributeManagerCategoryValue
    const btn = event.submitter || form.querySelector('button[type="submit"]')
    const originalText = btn.innerHTML
    btn.disabled = true
    btn.innerHTML = '<span class="ax-attribute-modal__spinner ax-attribute-modal__spinner--button" role="status"></span>'

    try {
      const response = await fetch(`/admin/attribute_options/${id}.json`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        credentials: "same-origin",
        body: JSON.stringify({
          attribute_option: {
            name: trimmed,
            context: context,
            category: category
          }
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        this.showMessage(errorData.name ? `Erro: ${errorData.name.join(", ")}` : "Erro ao atualizar.", "danger")
        return
      }

      this.renameOptionInUI(oldName, trimmed)
      this.fetchAttributes()
      this.showMessage("Opção atualizada.", "success")
    } catch (error) {
      console.error("Error updating attribute:", error)
      this.showMessage("Erro de conexão ao atualizar atributo.", "danger")
    } finally {
      btn.disabled = false
      btn.innerHTML = originalText
    }
  }

  // Helper: Update the TomSelect or Standard Select in the form
  appendOptionToUI(attr) {
    if (!this.targetSelectId) return

    const container = document.getElementById(this.targetSelectId)
    if (!container) return

    if (container.tomselect) {
      if (!container.tomselect.options[attr.name]) {
        container.tomselect.addOption({ value: attr.name, text: attr.name })
      }
      if (!container.tomselect.items.includes(attr.name)) {
        container.tomselect.addItem(attr.name)
      }

    } else if (container.tagName === 'DIV' && container.id.includes('checkbox-list')) {
      const escapedName = this.escapeHtml(attr.name)
      const label = document.createElement('label')
      label.className = 'custom-checkbox-card ax-chip-grid__item is-checked'

      label.innerHTML = `
        <input type="checkbox" name="${this.fieldNameValue}" value="${escapedName}" checked>
        <span title="${escapedName}">${escapedName}</span>
      `
      container.appendChild(label)

    } else {
      const option = new Option(attr.name, attr.name)
      container.add(option, undefined)
    }
  }

  removeOptionFromUI(name) {
    if (!this.targetSelectId) return
    const container = document.getElementById(this.targetSelectId)
    if (!container) return

    if (container.tomselect) {
      container.tomselect.removeItem(name, true)
      container.tomselect.removeOption(name)
    } else if (container.tagName === 'DIV' && container.id.includes('checkbox-list')) {
      const checkbox = Array.from(container.querySelectorAll("input[type='checkbox']")).find((el) => el.value === name)
      if (checkbox) checkbox.closest('.custom-checkbox-card, .ax-chip-grid__item')?.remove()
    } else {
      for (let i = 0; i < container.options.length; i++) {
        if (container.options[i].value === name) {
          container.remove(i)
          break
        }
      }
    }
  }

  renameOptionInUI(oldName, newName) {
    if (!this.targetSelectId) return
    const container = document.getElementById(this.targetSelectId)
    if (!container) return

    if (container.tomselect) {
      const wasSelected = container.tomselect.items.includes(oldName)
      if (wasSelected) container.tomselect.removeItem(oldName, true)
      container.tomselect.removeOption(oldName)
      container.tomselect.addOption({ value: newName, text: newName })
      if (wasSelected) container.tomselect.addItem(newName)
      return
    }

    if (container.tagName === "DIV" && container.id.includes("checkbox-list")) {
      const checkbox = Array.from(container.querySelectorAll("input[type='checkbox']")).find((el) => el.value === oldName)
      if (!checkbox) return
      checkbox.value = newName
      const label = checkbox.closest("label")?.querySelector("span")
      if (label) {
        label.textContent = newName
        label.title = newName
      }
      return
    }

    const option = Array.from(container.options).find((opt) => opt.value === oldName)
    if (option) {
      option.value = newName
      option.text = newName
    }
  }
}
