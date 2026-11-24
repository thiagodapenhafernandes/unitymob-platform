import { Controller } from "@hotwired/stimulus"

// Atualiza o select de etapa quando o funil muda no cadastro de lead.
// O formulário continua enviando `status`; o id da etapa é um vínculo mais
// preciso para o controller Rails reconciliar funil/etapa sem depender do nome.
export default class extends Controller {
  static targets = ["pipeline", "stage", "stageId", "businessType"]
  static values = { url: String, stages: Object, businessPipelines: Object, requireChoice: Boolean }

  connect() {
    this.syncStageId()
    this.lockBusinessPipeline()
  }

  lockBusinessPipeline() {
    if (!this.hasBusinessTypeTarget) return
    this.pipelineTarget.disabled = Boolean(this.businessPipelinesValue[this.businessTypeTarget.value])
  }

  changeBusinessType() {
    const pipelineId = this.businessPipelinesValue[this.businessTypeTarget.value]
    if (pipelineId) {
      this.pipelineTarget.value = String(pipelineId)
      this.changePipeline()
    }
    this.lockBusinessPipeline()
  }

  changePipeline() {
    const pipelineId = this.pipelineTarget.value
    if (!pipelineId) return
    if (this.hasStagesValue) {
      this.replaceStageOptions(this.stagesValue[pipelineId], this.stageTarget.value)
      return
    }
    if (!this.hasUrlValue) return

    const previousValue = this.stageTarget.value
    this.setLoading(true)

    fetch(this.stagesUrl(pipelineId), { headers: { Accept: "application/json" } })
      .then((response) => {
        if (!response.ok) throw new Error("Nao foi possivel carregar as etapas do funil.")
        return response.json()
      })
      .then((stages) => {
        this.replaceStageOptions(stages, previousValue)
      })
      .catch((error) => {
        console.warn("[lead-pipeline-stage-select] changePipeline:", error)
        this.syncStageId()
      })
      .finally(() => {
        this.setLoading(false)
      })
  }

  changeStage() {
    this.syncStageId()
  }

  replaceStageOptions(stages, previousValue) {
    const normalizedStages = Array.isArray(stages) ? stages : []
    this.emptyStageOptions = normalizedStages.length === 0
    this.stageTarget.replaceChildren()

    if (this.emptyStageOptions) {
      this.stageTarget.add(new Option("Nenhuma etapa cadastrada", ""))
      this.stageTarget.disabled = true
      this.stageIdTarget.value = ""
      return
    }

    normalizedStages.forEach((stage) => {
      const option = new Option(stage.name, stage.name)
      option.dataset.stageId = stage.id
      this.stageTarget.add(option)
    })

    const normalize = (value) => value.normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_|_$/g, "")
    const matched = Array.from(this.stageTarget.options).find((option) => normalize(option.value) === normalize(previousValue))
    if (!matched && this.requireChoiceValue) {
      this.stageTarget.add(new Option("Escolha uma etapa", ""), 0)
    }
    this.stageTarget.value = matched?.value || (this.requireChoiceValue ? "" : this.stageTarget.options[0]?.value) || ""
    this.syncStageId()
  }

  stagesUrl(pipelineId) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("lead_pipeline_id", pipelineId)
    return url.toString()
  }

  syncStageId() {
    if (!this.hasStageIdTarget || !this.hasStageTarget) return

    const selected = this.stageTarget.selectedOptions[0]
    this.stageIdTarget.value = selected?.dataset.stageId || ""
  }

  setLoading(loading) {
    this.stageTarget.disabled = loading || this.emptyStageOptions === true
    this.stageTarget.classList.toggle("is-loading", loading)
  }
}
