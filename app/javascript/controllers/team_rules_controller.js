import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Sincroniza o tom-select multi-valor com a fila de distribution_rule_agents
// que é renderizada como nested form. Qualquer mudança no select (add/remove
// chips) reflete instantaneamente na fila abaixo — sem botão "Adicionar".
export default class extends Controller {
  static targets = ["agentSelect", "list", "template"]
  static values = {
    structure: Object
  }

  connect() {
    this.initAgentSelect()
  }

  disconnect() {
    if (this.agentSelectInstance && this.agentSelectInstance.destroy) {
      try { this.agentSelectInstance.destroy() } catch (e) {}
    }
    this.agentSelectInstance = null
  }

  initAgentSelect() {
    if (!this.hasAgentSelectTarget) return
    if (this.agentSelectInstance) return
    // Elemento pode já ter TomSelect (ex: Turbo restaurando página cacheada)
    if (this.agentSelectTarget.tomselect) {
      this.agentSelectInstance = this.agentSelectTarget.tomselect
      return
    }

    this.agentSelectInstance = new TomSelect(this.agentSelectTarget, {
      plugins: ['remove_button'],
      placeholder: "Busque e selecione corretores…",
      maxOptions: null,
      onChange: (value) => this.syncQueue(value),
      onItemRemove: (value) => this.markForDestroy(value)
    })
  }

  // Recebe value que pode ser array (multi) ou string (single)
  syncQueue(value) {
    const selectedIds = this.normalizeSelectedIds(value)
    const currentIds  = this.currentQueueIds()

    // Adiciona os que não existem ainda
    selectedIds.forEach((id) => {
      if (!currentIds.includes(id)) this.addAgentToQueue(id)
      else this.restoreIfDestroyed(id)
    })

    // Marca pra destruir os que sumiram do select
    currentIds.forEach((id) => {
      if (!selectedIds.includes(id)) this.markForDestroy(id)
    })
  }

  normalizeSelectedIds(value) {
    if (Array.isArray(value)) return value.map(String).filter(Boolean)
    if (!value) return []
    return [String(value)]
  }

  currentQueueIds() {
    return Array.from(this.listTarget.querySelectorAll('input[name*="[admin_user_id]"]'))
      .filter((el) => {
        const wrapper = el.closest(".nested-form-wrapper")
        if (!wrapper) return false
        const destroyFlag = wrapper.querySelector('input[name*="[_destroy]"]')
        return destroyFlag && destroyFlag.value !== "1"
      })
      .map((el) => String(el.value))
  }

  addAgentToQueue(id) {
    const option = this.agentSelectInstance.options[id]
    const agentName = option ? option.text : "Corretor"

    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime() + "_" + id)
    this.listTarget.insertAdjacentHTML('beforeend', content)

    const newRow = this.listTarget.lastElementChild
    const idInput = newRow.querySelector('input[name*="[admin_user_id]"]')
    if (idInput) idInput.value = id

    const nameEl = newRow.querySelector('h6')
    if (nameEl) nameEl.textContent = agentName

    const subtitle = newRow.querySelector('.text-muted.extra-small')
    if (subtitle) subtitle.textContent = ''

    const avatar = newRow.querySelector('.rounded-circle span')
    if (avatar) avatar.textContent = agentName.substring(0, 2).toUpperCase()

    this.updateVisibility(newRow)
  }

  restoreIfDestroyed(id) {
    const input = this.findInputForId(id)
    if (!input) return
    const wrapper = input.closest(".nested-form-wrapper")
    if (!wrapper) return
    const destroyFlag = wrapper.querySelector('input[name*="[_destroy]"]')
    if (destroyFlag && destroyFlag.value === "1") {
      wrapper.style.display = ""
      destroyFlag.value = "0"
      this.updateVisibility(wrapper)
    }
  }

  markForDestroy(id) {
    const input = this.findInputForId(id)
    if (!input) return
    const wrapper = input.closest(".nested-form-wrapper")
    if (!wrapper) return

    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      wrapper.style.display = "none"
      const destroyFlag = wrapper.querySelector('input[name*="[_destroy]"]')
      if (destroyFlag) destroyFlag.value = "1"
    }
  }

  findInputForId(id) {
    const inputs = this.listTarget.querySelectorAll('input[name*="[admin_user_id]"]')
    for (const input of inputs) {
      if (String(input.value) === String(id)) return input
    }
    return null
  }

  // Chamado quando usuário clica no "X" do chip dentro de um item já na fila
  // (mantido pra quem remove pelo próprio wrapper da lista, não pelo tom-select)
  remove(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-form-wrapper")
    const input = wrapper?.querySelector('input[name*="[admin_user_id]"]')
    const id = input?.value

    if (id && this.agentSelectInstance) {
      this.agentSelectInstance.removeItem(String(id), true)
    }

    this.markForDestroy(id)
  }

  updateVisibility(row) {
    const currentMode = document.querySelector('input[name="distribution_rule[distribution_mode]"]:checked')?.value || 'rotary'
    const performanceField = row.querySelector('.performance-field')
    const rotaryField = row.querySelector('.rotary-field')

    if (performanceField) this.setVisible(performanceField, currentMode === 'performance')
    if (rotaryField) this.setVisible(rotaryField, currentMode === 'rotary')
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle('tw-hidden', !visible)
  }

  filterAgents(event) {
    const managerId = event.target.value
    if (!this.agentSelectInstance) return

    if (!managerId) {
      this.restoreAllOptions()
      return
    }

    const team = this.structureValue[managerId]
    if (!team) return

    const currentlySelected = this.agentSelectInstance.getValue()
    this.agentSelectInstance.clearOptions()
    team.agents.forEach(agent => {
      this.agentSelectInstance.addOption({ value: agent.id, text: agent.name })
    })
    // Preserva chips já selecionados mesmo que não estejam na nova lista
    Array.from(currentlySelected).forEach((id) => {
      if (!this.agentSelectInstance.options[id]) {
        const row = this.findInputForId(id)?.closest(".nested-form-wrapper")
        const name = row?.querySelector("h6")?.textContent || "Corretor"
        this.agentSelectInstance.addOption({ value: id, text: name })
      }
    })
    this.agentSelectInstance.refreshOptions(false)
  }

  restoreAllOptions() {
    if (!this.agentSelectInstance) return
    const currentlySelected = this.agentSelectInstance.getValue()
    this.agentSelectInstance.clearOptions()

    const seen = new Set()
    Object.values(this.structureValue).forEach(team => {
      team.agents.forEach(agent => {
        if (!seen.has(String(agent.id))) {
          seen.add(String(agent.id))
          this.agentSelectInstance.addOption({ value: agent.id, text: agent.name })
        }
      })
    })
    Array.from(currentlySelected).forEach((id) => {
      if (!this.agentSelectInstance.options[id]) {
        const row = this.findInputForId(id)?.closest(".nested-form-wrapper")
        const name = row?.querySelector("h6")?.textContent || "Corretor"
        this.agentSelectInstance.addOption({ value: id, text: name })
      }
    })
    this.agentSelectInstance.refreshOptions(false)
  }
}
