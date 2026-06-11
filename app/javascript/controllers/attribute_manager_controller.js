import { Controller } from "@hotwired/stimulus"
// Universal Attribute Manager
// Connects a "Manage" button to a Modal for CRUD operations on AttributeOptions
export default class extends Controller {
  static values = {
    context: String,
    category: String,
    fieldName: String, // e.g. "habitation[caracteristicas][]"
    modalId: { type: String, default: "attributeManagerModal" }
  }

  connect() {
    const modalElement = document.getElementById(this.modalIdValue)
    if (!modalElement || typeof bootstrap === "undefined" || !bootstrap.Modal) {
      console.error("AttributeManager: modal/bootstrap indisponível", { modalId: this.modalIdValue })
      return
    }

    this.modal = new bootstrap.Modal(modalElement)
  }

  // Action: Open Modal and Fetch Data
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
      alert("Contexto/categoria não definidos para este gerenciador.")
      return
    }
    if (!this.modal) {
      alert("Modal indisponível no momento. Recarregue a página.")
      return
    }

    this.fetchAttributes()
    this.modal.show()

    const title = btn.dataset.title || "Gerenciar Atributos"
    document.getElementById(`${this.modalIdValue}Title`).textContent = title
  }

  async fetchAttributes() {
    const listContainer = document.getElementById(`${this.modalIdValue}List`)
    listContainer.innerHTML = '<div class="text-center p-3"><div class="spinner-border text-primary" role="status"></div></div>'

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
      listContainer.innerHTML = '<p class="text-danger text-center">Erro ao carregar opções.</p>'
    }
  }

  renderList(attributes) {
    const listContainer = document.getElementById(`${this.modalIdValue}List`)

    if (attributes.length === 0) {
      listContainer.innerHTML = '<p class="text-muted text-center py-3">Nenhum atributo cadastrado.</p>'
      return
    }

    let html = '<ul class="list-group list-group-flush">'
    attributes.forEach(attr => {
      html += `
        <li class="list-group-item d-flex justify-content-between align-items-center px-2 py-2 border-bottom">
          <span class="small">${attr.name}</span>
          <div class="d-flex align-items-center gap-2">
            <button type="button" class="btn btn-sm btn-link text-primary p-0"
                    data-action="click->attribute-manager#edit"
                    data-id="${attr.id}"
                    data-name="${attr.name}"
                    title="Renomear">
              <i class="bi bi-pencil"></i>
            </button>
            <button type="button" class="btn btn-sm btn-link text-danger p-0"
                    data-action="click->attribute-manager#delete"
                    data-id="${attr.id}"
                    data-name="${attr.name}"
                    title="Excluir">
              <i class="bi bi-trash"></i>
            </button>
          </div>
        </li>
      `
    })
    html += '</ul>'
    listContainer.innerHTML = html
  }

  // Action: Create New Attribute
  async create(event) {
    event.preventDefault()
    const input = document.getElementById(`${this.modalIdValue}Input`)
    const name = input.value.trim()
    const context = this.contextValue || this.element.dataset.attributeManagerContextValue
    const category = this.categoryValue || this.element.dataset.attributeManagerCategoryValue

    if (!name) return
    if (!context || !category) {
      alert("Não foi possível identificar o contexto do atributo. Feche e abra o modal novamente.")
      return
    }

    const btn = event.submitter || event.currentTarget.querySelector('button[type="submit"]')
    const originalText = btn.innerHTML
    btn.disabled = true
    btn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status"></span>'

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
      } else {
        let errorData = null
        try {
          errorData = await response.json()
        } catch (_e) {
          errorData = null
        }
        console.error("Server error:", response.status, errorData)
        alert(errorData?.name ? `Erro: ${errorData.name.join(", ")}` : `Erro ao salvar (HTTP ${response.status}).`)
      }
    } catch (error) {
      console.error("Connection error:", error)
      alert("Erro de conexão. Verifique o console do navegador.")
    } finally {
      btn.disabled = false
      btn.innerHTML = originalText
    }
  }

  // Action: Delete Attribute
  async delete(event) {
    if (!confirm("Tem certeza? Isso não removerá o atributo dos imóveis que já o possuem, apenas da lista de opções.")) return

    const btn = event.currentTarget
    const id = btn.dataset.id
    const name = btn.dataset.name

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
      } else {
        alert("Erro ao excluir.")
      }
    } catch (error) {
      console.error("Error deleting attribute:", error)
    }
  }

  async edit(event) {
    const btn = event.currentTarget
    const id = btn.dataset.id
    const oldName = btn.dataset.name
    const newName = prompt("Novo nome do atributo:", oldName)

    if (!newName) return
    const trimmed = newName.trim()
    if (!trimmed || trimmed === oldName) return
    const context = this.contextValue || this.element.dataset.attributeManagerContextValue
    const category = this.categoryValue || this.element.dataset.attributeManagerCategoryValue

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
        alert(errorData.name ? `Erro: ${errorData.name.join(", ")}` : "Erro ao atualizar.")
        return
      }

      this.renameOptionInUI(oldName, trimmed)
      this.fetchAttributes()
    } catch (error) {
      console.error("Error updating attribute:", error)
      alert("Erro de conexão ao atualizar atributo.")
    }
  }

  // Helper: Update the TomSelect or Standard Select in the form
  appendOptionToUI(attr) {
    if (!this.targetSelectId) return

    const container = document.getElementById(this.targetSelectId)
    if (!container) return

    // Check if it's a TomSelect
    if (container.tomselect) {
      container.tomselect.addOption({ value: attr.name, text: attr.name })
      container.tomselect.addItem(attr.name) // Optional: select it immediately

      // Check if it's a Checkbox Container (div)
    } else if (container.tagName === 'DIV' && container.id.includes('checkbox-list')) {
      const col = document.createElement('div')
      col.className = 'col animate__animated animate__fadeIn'

      col.innerHTML = `
        <label class="custom-checkbox-card w-100 h-100">
          <input type="checkbox" name="${this.fieldNameValue}" value="${attr.name}" class="form-check-input mt-0" checked>
          <span class="extra-small fw-semibold text-truncate ms-2" title="${attr.name}">${attr.name}</span>
        </label>
      `
      container.appendChild(col)

    } else {
      // Standard Select
      const option = new Option(attr.name, attr.name)
      container.add(option, undefined)
    }
  }

  removeOptionFromUI(name) {
    if (!this.targetSelectId) return
    const container = document.getElementById(this.targetSelectId)
    if (!container) return

    if (container.tomselect) {
      container.tomselect.removeOption(name)
      container.tomselect.removeItem(name, true)
    } else if (container.tagName === 'DIV' && container.id.includes('checkbox-list')) {
      const checkbox = Array.from(container.querySelectorAll("input[type='checkbox']")).find((el) => el.value === name)
      if (checkbox) checkbox.closest('.col').remove()
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
