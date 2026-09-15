import { Controller } from "@hotwired/stimulus"

// Divulgação progressiva da tela de Configurações de Leads: as sub-opções de
// fidelização e a validade do link seguro só aparecem quando o respectivo
// toggle está ligado.
export default class extends Controller {
  static targets = ["stickinessSection", "secureSection", "slaValue", "slaUnit", "slaHint"]

  connect() {
    this.toggleStickiness()
    this.toggleSecure()
    this.syncSlaDuration()
  }

  findCheckbox(name) {
    return this.element.querySelector(`input[type="checkbox"][name="${name}"]`)
  }

  toggleStickiness(event) {
    const cb = event ? event.target : this.findCheckbox("lead_setting[stickiness_enabled]")
    if (this.hasStickinessSectionTarget && cb) this.setVisible(this.stickinessSectionTarget, cb.checked)
  }

  toggleSecure(event) {
    const cb = event ? event.target : this.findCheckbox("lead_setting[secure_links_enabled]")
    if (this.hasSecureSectionTarget && cb) this.setVisible(this.secureSectionTarget, cb.checked)
  }

  limitStageAutomationInterval(event) {
    const input = event.target
    const max = Number.parseInt(input.dataset.leadSettingsMaxValue, 10)
    const value = Number.parseInt(input.value, 10)

    if (Number.isFinite(max) && Number.isFinite(value) && value > max) {
      input.value = max
    }
  }

  clampStageAutomationInterval(event) {
    const input = event.target
    const min = Number.parseInt(input.dataset.leadSettingsMinValue, 10)
    const max = Number.parseInt(input.dataset.leadSettingsMaxValue, 10)
    const value = Number.parseInt(input.value, 10)

    if (!Number.isFinite(value) && Number.isFinite(min)) {
      input.value = min
    } else if (Number.isFinite(min) && value < min) {
      input.value = min
    } else if (Number.isFinite(max) && value > max) {
      input.value = max
    }
  }

  syncSlaDuration() {
    if (!this.hasSlaValueTarget || !this.hasSlaUnitTarget) return

    const config = this.slaDurationConfig()
    this.slaValueTarget.min = config.min
    this.slaValueTarget.max = config.max
    this.slaValueTarget.placeholder = config.placeholder
    this.clampNumberInput(this.slaValueTarget, config.min, config.max)

    if (this.hasSlaHintTarget) {
      this.slaHintTarget.textContent = `Usado no dashboard e nos filtros de leads para apontar quem passou de ${this.slaValueTarget.value || config.placeholder} ${config.label} sem primeiro atendimento.`
    }
  }

  limitSlaDuration(event) {
    const config = this.slaDurationConfig()
    const value = Number.parseInt(event.target.value, 10)
    if (Number.isFinite(value) && value > config.max) event.target.value = config.max
    if (this.hasSlaHintTarget) this.syncSlaDuration()
  }

  clampSlaDuration(event) {
    const config = this.slaDurationConfig()
    this.clampNumberInput(event.target, config.min, config.max)
    if (this.hasSlaHintTarget) this.syncSlaDuration()
  }

  slaDurationConfig() {
    const unit = this.hasSlaUnitTarget ? this.slaUnitTarget.value : "hours"
    return {
      minutes: { min: 1, max: 43200, placeholder: 240, label: "minutos" },
      hours: { min: 1, max: 720, placeholder: 4, label: "horas" },
      days: { min: 1, max: 30, placeholder: 1, label: "dias" }
    }[unit] || { min: 1, max: 720, placeholder: 4, label: "horas" }
  }

  clampNumberInput(input, min, max) {
    const value = Number.parseInt(input.value, 10)

    if (!Number.isFinite(value)) {
      input.value = min
    } else if (value < min) {
      input.value = min
    } else if (value > max) {
      input.value = max
    }
  }

  setVisible(el, visible) {
    el.hidden = !visible
    el.classList.toggle("tw-hidden", !visible)
  }
}
