import { Controller } from "@hotwired/stimulus"

// Divulgação progressiva da tela de Configurações de Leads: as sub-opções de
// fidelização e a validade do link seguro só aparecem quando o respectivo
// toggle está ligado.
export default class extends Controller {
  static targets = ["stickinessSection", "secureSection"]

  connect() {
    this.toggleStickiness()
    this.toggleSecure()
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

  setVisible(el, visible) {
    el.hidden = !visible
    el.classList.toggle("tw-hidden", !visible)
  }
}
