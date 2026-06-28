import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "step",
    "stepButton",
    "progress",
    "audienceCount",
    "audienceMeta",
    "audienceSample",
    "audienceTotal",
    "audienceWithPhone",
    "audienceInvalid",
    "audienceMode",
    "audienceModeCard",
    "audienceModePanel",
    "conditionList",
    "conditionTemplate",
    "conditionRow",
    "reviewName",
    "reviewSender",
    "reviewGroup",
    "reviewTemplate",
    "reviewAudience",
    "reviewSchedule",
    "reviewVariables",
    "templatePreview",
    "testPhone",
    "testResult",
    "templateSelect",
    "senderSelect",
    "groupInput",
    "nameInput",
    "scheduledInput",
    "sendRateInput",
    "variableList",
    "variableInput",
    "responseDecisionList",
    "responseDecisionRow",
    "responseDecisionInput",
    "scheduleSubmit",
    "startNowSubmit"
  ]

  static values = {
    currentStep: { type: Number, default: 1 },
    previewUrl: String,
    templatePreviewUrl: String,
    testUrl: String,
    responseActions: Object,
    distributionRules: Array,
    currentResponseDecisions: Object
  }

  connect() {
    this.audiencePreviewReady = false
    this.showStep(this.currentStepValue || 1)
    this.toggleAudienceMode()
    this.conditionRowTargets.forEach((row) => this.syncConditionRow({ currentTarget: row }))
    this.refreshReview()
    if (this.hasTemplateSelectTarget && this.templateSelectTarget.value) this.previewTemplate()
  }

  next() {
    if (!this.validateCurrentStep()) return
    this.showStep(Math.min(this.currentStepValue + 1, this.stepTargets.length))
  }

  previous() {
    this.showStep(Math.max(this.currentStepValue - 1, 1))
  }

  goTo(event) {
    const step = Number(event.currentTarget.dataset.step)
    if (!step) return
    if (step > this.currentStepValue && !this.validateCurrentStep()) return
    this.showStep(step)
  }

  refreshReview() {
    if (this.hasReviewNameTarget && this.hasNameInputTarget) {
      this.reviewNameTarget.textContent = this.nameInputTarget.value || "Sem nome"
    }

    if (this.hasReviewTemplateTarget && this.hasTemplateSelectTarget) {
      const selected = this.templateSelectTarget.selectedOptions[0]
      this.reviewTemplateTarget.textContent = selected?.textContent?.trim() || "Modelo nao selecionado"
    }

    if (this.hasReviewSenderTarget && this.hasSenderSelectTarget) {
      const selected = this.senderSelectTarget.selectedOptions[0]
      this.reviewSenderTarget.textContent = selected?.textContent?.trim() || "Numero padrao"
    }

    if (this.hasReviewGroupTarget && this.hasGroupInputTarget) {
      this.reviewGroupTarget.textContent = this.groupInputTarget.value || "Sem grupo"
    }

    if (this.hasReviewScheduleTarget) {
      const schedule = this.hasScheduledInputTarget ? this.scheduledInputTarget.value : ""
      const rate = this.hasSendRateInputTarget ? this.sendRateInputTarget.value : ""
      this.reviewScheduleTarget.textContent = schedule ? `${schedule} - ${rate || "0"} envios/min` : `${rate || "0"} envios/min - envio manual`
    }

    if (this.hasReviewVariablesTarget) {
      const values = this.variableInputTargets
        .map((input) => `${input.dataset.variableKey || input.name}: ${this.selectedLabel(input)}`)
        .join(" | ")
      this.reviewVariablesTarget.textContent = values || "Sem variaveis"
    }
  }

  previewAudience(event) {
    event?.preventDefault()
    if (!this.previewUrlValue) return

    this.setAudienceLoading()
    this.audiencePreviewReady = false
    fetch(this.previewUrlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: this.ajaxFormData()
    })
      .then((response) => {
        if (!response.ok) throw new Error("Falha ao pré-visualizar audiência")
        return response.json()
      })
      .then((data) => this.renderAudience(data))
      .catch((error) => this.renderAudienceError(error))
  }

  prepareSpreadsheet(event) {
    event?.preventDefault()
    const fileInput = this.element.querySelector("input[type='file'][name='whatsapp_campaign[audience_file]']")
    const hasExistingFile = this.element.querySelector(".ax-file-field__filename")?.textContent?.trim()?.match(/\.csv$/i)

    if (!fileInput?.files?.length && !hasExistingFile) {
      this.showValidationError("Selecione um CSV antes de preparar a planilha.")
      return
    }

    this.previewAudience(event)
  }

  toggleAudienceMode() {
    const selected = this.selectedAudienceMode()
    this.audiencePreviewReady = false
    this.audienceModePanelTargets.forEach((panel) => {
      const active = panel.dataset.audienceMode === selected
      panel.hidden = !active
      panel.querySelectorAll("input, select, textarea, button").forEach((input) => {
        if (input.type === "button") return
        input.disabled = !active
      })
    })

    this.audienceModeCardTargets.forEach((card) => {
      const radio = card.querySelector("input[type='radio']")
      card.classList.toggle("is-selected", radio?.checked)
    })

    this.conditionRowTargets.forEach((row) => this.syncConditionRow({ currentTarget: row }))
    this.refreshReview()
  }

  addCondition(event) {
    event?.preventDefault()
    if (!this.hasConditionTemplateTarget || !this.hasConditionListTarget) return

    const index = Date.now().toString()
    const html = this.conditionTemplateTarget.innerHTML.replaceAll("__INDEX__", index)
    this.conditionListTarget.insertAdjacentHTML("beforeend", html)
    const row = this.conditionListTarget.lastElementChild
    this.syncConditionRow({ currentTarget: row })
  }

  duplicateCondition(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-campaign-builder-target~='conditionRow']")
    if (!row) return

    const index = Date.now().toString()
    const clone = row.cloneNode(true)
    clone.querySelectorAll("[name]").forEach((input) => {
      input.name = input.name.replace(/\[conditions\]\[[^\]]+\]/, `[conditions][${index}]`)
    })
    clone.querySelectorAll("[id]").forEach((input) => {
      input.id = input.id.replace(/conditions\]\[[^\]]+\]/, `conditions][${index}]`)
    })
    row.insertAdjacentElement("afterend", clone)
    this.syncConditionRow({ currentTarget: clone })
  }

  removeCondition(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-campaign-builder-target~='conditionRow']")
    if (!row) return

    row.remove()
    if (this.conditionRowTargets.length === 0) this.addCondition()
  }

  syncConditionRow(event) {
    if (event?.type === "change" || event?.type === "input") this.audiencePreviewReady = false
    const row = event.currentTarget.closest?.("[data-whatsapp-campaign-builder-target~='conditionRow']") || event.currentTarget
    if (!row) return

    const field = row.querySelector("[data-condition-field]")?.value || "status"
    const operator = row.querySelector("[data-condition-operator]")
    const modeActive = this.selectedAudienceMode() === "filters"
    const type = this.valueTypeForField(field)

    if (operator) {
      this.syncOperatorOptions(operator, field)
    }

    row.querySelectorAll("[data-condition-value-type]").forEach((group) => {
      const active = modeActive && group.dataset.conditionValueType === type
      group.hidden = !active
      group.querySelectorAll("input, select, textarea").forEach((input) => {
        input.disabled = !active
      })
    })
  }

  previewTemplate(event) {
    event?.preventDefault()
    if (!this.templatePreviewUrlValue) return

    const shouldRebuildVariables = !event || event.currentTarget === this.templateSelectTarget || this.variableInputTargets.length === 0
    if (this.hasTemplatePreviewTarget) this.templatePreviewTarget.textContent = "Gerando preview..."
    fetch(this.templatePreviewUrlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: this.ajaxFormData()
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) throw new Error(data.error || "Falha ao gerar preview")
        if (shouldRebuildVariables) this.renderVariableMapping(data.variables_schema || [])
        this.renderResponseDecisions(data.buttons || [])
        if (this.hasTemplatePreviewTarget) this.templatePreviewTarget.textContent = data.body || "Modelo sem corpo"
        this.refreshReview()
      })
      .catch((error) => {
        if (this.hasTemplatePreviewTarget) this.templatePreviewTarget.textContent = error.message
      })
  }

  sendTest(event) {
    event?.preventDefault()
    if (!this.testUrlValue) return

    const formData = this.ajaxFormData()
    if (this.hasTestPhoneTarget) formData.append("test_phone", this.testPhoneTarget.value)
    this.renderTestResult({ state: "loading", message: "Enviando teste..." })

    fetch(this.testUrlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: formData
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) {
          this.renderTestResult({
            state: "error",
            message: data.error || "Falha no envio de teste",
            hint: data.error_hint,
            metaError: data.meta_error
          })
          return
        }
        this.renderTestResult({
          state: "success",
          message: `Teste aceito pela Meta. WAMID: ${data.message_id || "-"}`,
          hint: data.delivery_hint || "A entrega é confirmada depois pelo webhook de status do WhatsApp."
        })
      })
      .catch((error) => {
        this.renderTestResult({ state: "error", message: error.message })
      })
  }

  showStep(step) {
    this.currentStepValue = step
    this.stepTargets.forEach((element) => {
      element.hidden = Number(element.dataset.step) !== step
    })
    this.stepButtonTargets.forEach((button) => {
      const active = Number(button.dataset.step) === step
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-current", active ? "step" : "false")
    })

    if (this.hasProgressTarget && this.stepTargets.length > 0) {
      this.progressTarget.style.width = `${(step / this.stepTargets.length) * 100}%`
    }

    this.updateFooterActions()
    this.refreshReview()
  }

  updateFooterActions() {
    if (this.hasScheduleSubmitTarget) {
      this.scheduleSubmitTarget.hidden = this.currentStepValue !== 4
    }

    if (this.hasStartNowSubmitTarget) {
      this.startNowSubmitTarget.hidden = this.currentStepValue !== 5
    }
  }

  setAudienceLoading() {
    if (this.hasAudienceCountTarget) this.audienceCountTarget.textContent = "Calculando..."
    if (this.hasAudienceMetaTarget) this.audienceMetaTarget.textContent = "Validando filtros e telefones"
    if (this.hasAudienceSampleTarget) this.audienceSampleTarget.innerHTML = ""
    if (this.hasAudienceTotalTarget) this.audienceTotalTarget.textContent = "--"
    if (this.hasAudienceWithPhoneTarget) this.audienceWithPhoneTarget.textContent = "--"
    if (this.hasAudienceInvalidTarget) this.audienceInvalidTarget.textContent = "--"
  }

  renderAudience(data) {
    if (data.ok === false) {
      this.renderAudienceError(new Error((data.errors || []).join(", ") || "Não foi possível calcular o público"))
      return
    }
    this.audiencePreviewReady = true

    if (this.hasAudienceCountTarget) this.audienceCountTarget.textContent = `${data.valid_phone_count || 0} destinatários com telefone`
    if (this.hasAudienceMetaTarget) {
      const invalid = data.invalid_count || data.without_phone_count || 0
      this.audienceMetaTarget.textContent = data.summary || `${data.total || 0} destinatários encontrados - ${invalid} ignorados`
    }
    if (this.hasAudienceTotalTarget) this.audienceTotalTarget.textContent = data.total || 0
    if (this.hasAudienceWithPhoneTarget) this.audienceWithPhoneTarget.textContent = data.valid_phone_count || 0
    if (this.hasAudienceInvalidTarget) {
      this.audienceInvalidTarget.textContent = data.invalid_count || data.without_phone_count || 0
    }
    if (this.hasReviewAudienceTarget) {
      this.reviewAudienceTarget.textContent = `${data.valid_phone_count || 0} aptos para envio (${data.total || 0} no filtro)`
    }
    if (this.hasAudienceSampleTarget) {
      this.audienceSampleTarget.innerHTML = (data.sample || []).map((recipient) => `
        <li>
          <strong>${this.escape(recipient.name || "Contato")}</strong>
          <span>${this.escape(recipient.phone || "-")} - ${this.escape(recipient.email || recipient.origin || "-")} - ${this.escape(recipient.responsible || "Sem responsável")}</span>
        </li>
      `).join("")
    }
  }

  renderAudienceError(error) {
    this.audiencePreviewReady = false
    if (this.hasAudienceCountTarget) this.audienceCountTarget.textContent = "Erro no preview"
    if (this.hasAudienceMetaTarget) this.audienceMetaTarget.textContent = error.message
    if (this.hasAudienceTotalTarget) this.audienceTotalTarget.textContent = "--"
    if (this.hasAudienceWithPhoneTarget) this.audienceWithPhoneTarget.textContent = "--"
    if (this.hasAudienceInvalidTarget) this.audienceInvalidTarget.textContent = "--"
  }

  renderTestResult({ state, message, hint, metaError }) {
    if (!this.hasTestResultTarget) return

    const classes = {
      loading: "whatsapp-test-result whatsapp-test-result--loading",
      success: "whatsapp-test-result whatsapp-test-result--success",
      error: "whatsapp-test-result whatsapp-test-result--error"
    }
    const icon = {
      loading: "bi-hourglass-split",
      success: "bi-check-circle",
      error: "bi-exclamation-triangle"
    }[state] || "bi-info-circle"
    const details = this.metaErrorDetails(metaError)

    this.testResultTarget.className = classes[state] || "whatsapp-test-result"
    this.testResultTarget.innerHTML = `
      <i class="bi ${icon}" aria-hidden="true"></i>
      <span>
        <strong>${this.escape(message || "")}</strong>
        ${hint ? `<small>${this.escape(hint)}</small>` : ""}
        ${details ? `<small>${this.escape(details)}</small>` : ""}
      </span>
    `
  }

  metaErrorDetails(metaError) {
    if (!metaError || typeof metaError !== "object") return ""

    const parts = []
    if (metaError.code) parts.push(`Código Meta: ${metaError.code}`)
    if (metaError.subcode) parts.push(`Subcódigo: ${metaError.subcode}`)
    if (metaError.trace_id) parts.push(`Trace: ${metaError.trace_id}`)
    return parts.join(" · ")
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  ajaxFormData() {
    const formData = new FormData(this.element)
    formData.delete("_method")
    return formData
  }

  escape(value) {
    const element = document.createElement("span")
    element.textContent = value
    return element.innerHTML
  }

  escapeAttribute(value) {
    return this.escape(value).replace(/"/g, "&quot;")
  }

  selectedLabel(input) {
    if (!input.value) return "-"
    return input.selectedOptions?.[0]?.textContent?.trim() || input.value
  }

  applyTemplateSuggestions(suggestions) {
    this.variableInputTargets.forEach((input) => {
      const key = input.name?.match(/\[template_variables\]\[(\d+)\]/)?.[1]
      const suggestion = suggestions[key]
      if (!suggestion || input.value) return

      input.value = suggestion
      input.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  renderVariableMapping(schema) {
    if (!this.hasVariableListTarget) return

    if (!schema.length) {
      this.variableListTarget.innerHTML = `
        <div class="ax-inline-notice ax-inline-notice--info">
          Este modelo não possui variáveis para mapear.
        </div>
      `
      return
    }

    const currentValues = new Map(
      this.variableInputTargets.map((input) => {
        const key = input.name?.match(/\[template_variables\]\[(\d+)\]/)?.[1]
        return [key, input.value]
      })
    )

    const options = this.templateVariableOptions()
    this.variableListTarget.innerHTML = `
      <div class="whatsapp-template-variable-map__head">
        <span>Variável no modelo</span>
        <span>Contexto detectado</span>
        <span>Preencher com</span>
      </div>
      ${schema.map((item) => {
        const index = String(item.index)
        const selected = currentValues.get(index) || item.selected || ""
        return `
          <div class="whatsapp-template-variable-row">
            <div class="whatsapp-template-variable-row__token">${this.escape(item.placeholder || `{{${index}}}`)}</div>
            <div class="whatsapp-template-variable-row__context">${this.escape(item.context || `Variável ${index}`)}</div>
            <select
              name="whatsapp_campaign[template_variables][${this.escape(index)}]"
              id="whatsapp_campaign_template_variables_${this.escape(index)}"
              class="ax-control"
              data-whatsapp-campaign-builder-target="variableInput"
              data-variable-key="${this.escape(item.placeholder || `{{${index}}}`)}"
              data-action="change->whatsapp-campaign-builder#refreshReview change->whatsapp-campaign-builder#previewTemplate">
              ${options.map((option) => `
                <option value="${this.escape(option.value)}" ${option.value === selected ? "selected" : ""}>${this.escape(option.label)}</option>
              `).join("")}
            </select>
          </div>
        `
      }).join("")}
    `
  }

  renderResponseDecisions(buttons) {
    if (!this.hasResponseDecisionListTarget) return

    if (!buttons.length) {
      this.responseDecisionListTarget.innerHTML = `
        <div class="ax-inline-notice ax-inline-notice--info">
          Este modelo não possui botões. Respostas por texto livre podem ser tratadas pela Automação na etapa "Aguardar resposta".
        </div>
      `
      return
    }

    this.responseDecisionListTarget.innerHTML = buttons.map((button, index) => {
      const decision = this.currentDecisionFor(button)
      const action = decision.action || button.action || "ignore"
      const distributionRuleId = decision.distribution_rule_id || button.distribution_rule_id || ""
      const message = decision.message || button.message || ""

      return `
        <div class="whatsapp-response-decision-row" data-whatsapp-campaign-builder-target="responseDecisionRow">
          <input type="hidden" name="whatsapp_campaign[response_decisions][buttons][${index}][key]" value="${this.escapeAttribute(button.key || "")}">
          <input type="hidden" name="whatsapp_campaign[response_decisions][buttons][${index}][text]" value="${this.escapeAttribute(button.text || "")}">
          <input type="hidden" name="whatsapp_campaign[response_decisions][buttons][${index}][kind]" value="${this.escapeAttribute(button.kind || "")}">
          <div class="whatsapp-response-decision-row__button">
            <span>${this.escape(button.text || "-")}</span>
            <small>${this.escape(button.context || button.kind_label || "Botão do template")}</small>
          </div>
          <div class="ax-field">
            <label class="ax-label">Quando clicarem</label>
            <select class="ax-control"
                    name="whatsapp_campaign[response_decisions][buttons][${index}][action]"
                    data-whatsapp-campaign-builder-target="responseDecisionInput"
                    data-action="change->whatsapp-campaign-builder#syncResponseDecisionRow change->whatsapp-campaign-builder#refreshReview">
              ${this.responseActionOptions(action)}
            </select>
          </div>
          <div class="ax-field" data-response-decision-extra="distribution_rule">
            <label class="ax-label">Regra de distribuição</label>
            <select class="ax-control" name="whatsapp_campaign[response_decisions][buttons][${index}][distribution_rule_id]">
              <option value="">Escolher regra...</option>
              ${this.distributionRuleOptions(distributionRuleId)}
            </select>
          </div>
          <div class="ax-field" data-response-decision-extra="message">
            <label class="ax-label">Mensagem automática</label>
            <input class="ax-control"
                   name="whatsapp_campaign[response_decisions][buttons][${index}][message]"
                   value="${this.escapeAttribute(message)}"
                   placeholder="Ex: Perfeito, vou te encaminhar para atendimento.">
          </div>
          <p class="whatsapp-response-decision-row__hint" data-response-decision-summary></p>
        </div>
      `
    }).join("")

    this.responseDecisionRowTargets.forEach((row) => this.syncResponseDecisionRow({ currentTarget: row }))
  }

  syncResponseDecisionRow(event) {
    const row = event.currentTarget.closest?.("[data-whatsapp-campaign-builder-target~='responseDecisionRow']") || event.currentTarget
    if (!row) return

    const action = row.querySelector("select[name*='[action]']")?.value || "ignore"
    row.querySelectorAll("[data-response-decision-extra]").forEach((element) => {
      const type = element.dataset.responseDecisionExtra
      const visible = (type === "distribution_rule" && action === "generate_lead") ||
        (type === "message" && action === "send_message")
      element.hidden = !visible
      element.querySelectorAll("input, select, textarea").forEach((input) => {
        input.disabled = !visible
      })
    })

    const summary = row.querySelector("[data-response-decision-summary]")
    if (summary) summary.textContent = this.responseDecisionSummary(action)
  }

  currentDecisionFor(button) {
    const key = String(button.key || "")
    const fromDom = this.responseDecisionInputTargets.find((input) => {
      const row = input.closest("[data-whatsapp-campaign-builder-target~='responseDecisionRow']")
      return row?.querySelector("input[name*='[key]']")?.value === key
    })
    if (fromDom) {
      const row = fromDom.closest("[data-whatsapp-campaign-builder-target~='responseDecisionRow']")
      return {
        action: fromDom.value,
        distribution_rule_id: row?.querySelector("select[name*='[distribution_rule_id]']")?.value || "",
        message: row?.querySelector("input[name*='[message]']")?.value || ""
      }
    }

    const rows = this.currentResponseDecisionsValue?.buttons || []
    return rows.find((item) => String(item.key || "") === key) || {}
  }

  responseActionOptions(selected) {
    const actions = this.responseActionsValue || {}
    return Object.entries(actions).map(([value, label]) => `
      <option value="${this.escapeAttribute(value)}" ${value === selected ? "selected" : ""}>${this.escape(label)}</option>
    `).join("")
  }

  distributionRuleOptions(selected) {
    const rules = this.distributionRulesValue || []
    return rules.map((row) => {
      const label = Array.isArray(row) ? row[0] : row.label
      const value = String(Array.isArray(row) ? row[1] : row.value)
      return `<option value="${this.escapeAttribute(value)}" ${value === String(selected || "") ? "selected" : ""}>${this.escape(label)}</option>`
    }).join("")
  }

  responseDecisionSummary(action) {
    return {
      generate_lead: "Converte o destinatário em lead e envia para a regra selecionada.",
      send_message: "Registra a resposta e envia uma mensagem automática no WhatsApp.",
      create_task: "Registra a resposta para a equipe atuar com uma tarefa comercial.",
      mark_no_interest: "Registra a resposta como sem interesse, sem criar lead de atendimento.",
      unsubscribe: "Marca o contato como descadastrado para futuras campanhas.",
      ignore: "Apenas registra a resposta para relatório e automações futuras."
    }[action] || "Apenas registra a resposta."
  }

  templateVariableOptions() {
    return [
      { label: "Escolher campo...", value: "" },
      { label: "Nome do destinatário", value: "{{nome}}" },
      { label: "Telefone do destinatário", value: "{{telefone}}" },
      { label: "E-mail do destinatário", value: "{{email}}" },
      { label: "Origem / fonte", value: "{{origem}}" },
      { label: "Status / etapa do funil", value: "{{status}}" },
      { label: "Tags do destinatário", value: "{{tags}}" },
      { label: "Produto / imóvel", value: "{{produto}}" },
      { label: "Empresa / número de envio", value: "{{empresa}}" },
      { label: "Observações", value: "{{observacoes}}" },
      { label: "Responsável pelo atendimento", value: "{{corretor}}" },
      { label: "Telefone do responsável", value: "{{corretor_telefone}}" },
      { label: "E-mail do responsável", value: "{{corretor_email}}" }
    ]
  }

  validateCurrentStep() {
    if (this.currentStepValue === 1) {
      if (!this.hasNameInputTarget || this.nameInputTarget.value.trim().length === 0) {
        this.showValidationError("Informe o nome do disparo antes de avançar.")
        return false
      }
    }

    if (this.currentStepValue === 2) {
      if (!this.hasTemplateSelectTarget || this.templateSelectTarget.value.trim().length === 0) {
        this.showValidationError("Selecione um modelo WhatsApp aprovado antes de avançar.")
        return false
      }

      const invalidDecision = this.responseDecisionRowTargets.find((row) => {
        const action = row.querySelector("select[name*='[action]']")?.value
        const rule = row.querySelector("select[name*='[distribution_rule_id]']")?.value
        return action === "generate_lead" && !rule
      })
      if (invalidDecision) {
        this.showValidationError("Para converter uma resposta em lead, escolha a regra de distribuição desse botão.")
        return false
      }
    }

    if (this.currentStepValue === 3) {
      const mode = this.selectedAudienceMode()
      if (mode === "saved_audience") {
        this.showValidationError("Público salvo ainda não está habilitado para envio.")
        return false
      }

      if (!this.audiencePreviewReady) {
        this.showValidationError(mode === "spreadsheet" ? "Prepare a planilha e valide a audiência antes de avançar." : "Pré-visualize a audiência antes de avançar.")
        return false
      }
    }

    if (this.currentStepValue === 4 && this.hasSendRateInputTarget) {
      const rate = Number(this.sendRateInputTarget.value)
      if (!rate || rate < 1 || rate > 500) {
        this.showValidationError("Informe uma velocidade de envio entre 1 e 500 mensagens por minuto.")
        return false
      }
    }

    return true
  }

  showValidationError(message) {
    if (this.hasAudienceMetaTarget && this.currentStepValue === 3) {
      this.audienceMetaTarget.textContent = message
    }
    window.alert(message)
  }

  selectedAudienceMode() {
    return this.audienceModeTargets.find((input) => input.checked)?.value || "filters"
  }

  valueTypeForField(field) {
    if (field === "status") return "status"
    if (field === "origin") return "origin"
    if (field === "admin_user_id") return "admin_user_id"
    if (field === "tags") return "tags"
    if (field === "created_at") return "created_at"
    return "text"
  }

  syncOperatorOptions(select, field) {
    const allowed = {
      status: ["in", "equals"],
      origin: ["in", "contains", "equals"],
      admin_user_id: ["equals", "in"],
      tags: ["with_any", "without_any"],
      created_at: ["between", "since", "until"],
      name: ["contains", "equals"],
      email: ["contains", "present", "blank"],
      phone: ["contains", "present", "blank"]
    }[field] || ["contains", "equals"]

    Array.from(select.options).forEach((option) => {
      option.hidden = !allowed.includes(option.value)
      option.disabled = !allowed.includes(option.value)
    })

    if (!allowed.includes(select.value)) {
      select.value = allowed[0]
    }
  }
}
