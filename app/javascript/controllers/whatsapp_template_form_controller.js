import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "bodyInput",
    "buttonList",
    "buttonRow",
    "carouselCardList",
    "carouselCardRow",
    "exampleInput",
    "exampleRow",
    "examplesList",
    "flowActionSelect",
    "flowScreenField",
    "headerTextField",
    "mediaSelect",
    "mediaField",
    "mediaRules"
  ]
  static values = {
    uploadMediaUrl: String
  }

  connect() {
    this.toggleMedia()
    this.toggleButtonRows()
    this.toggleCarouselButtonRows()
    this.toggleFlowFields()
    this.refreshCarouselIndexes()
    this.syncExamples()
  }

  toggleMedia() {
    if (!this.hasMediaSelectTarget) return

    const value = this.mediaSelectTarget.value
    const hasMedia = ["image", "video", "document"].includes(value)
    const hasText = value === "text"
    if (this.hasHeaderTextFieldTarget) this.headerTextFieldTarget.hidden = !hasText
    if (this.hasMediaFieldTarget) this.mediaFieldTarget.hidden = !hasMedia
    if (this.hasMediaRulesTarget) this.mediaRulesTarget.hidden = !hasMedia

    const handleInput = this.element.querySelector("input[name='whatsapp_template[header_media_handle]']")
    if (handleInput && !hasMedia) handleInput.value = ""
  }

  toggleFlowFields() {
    if (!this.hasFlowActionSelectTarget || !this.hasFlowScreenFieldTarget) return

    this.flowScreenFieldTarget.hidden = this.flowActionSelectTarget.value !== "navigate"
  }

  syncExamples() {
    const expected = this.expectedExampleCount()
    if (!this.hasExamplesListTarget) return

    while (this.exampleRowTargets.length < expected) this.addExampleRow()
    this.refreshExampleLabels()
  }

  addExample(event) {
    event?.preventDefault()
    this.addExampleRow()
    this.refreshExampleLabels()
  }

  addButton(event) {
    event?.preventDefault()
    if (!this.hasButtonListTarget || this.buttonRowTargets.length >= 3) return

    this.buttonListTarget.insertAdjacentHTML("beforeend", this.buttonRowTemplate(this.buttonRowTargets.length))
    this.refreshButtonIndexes()
    this.toggleButtonRows()
  }

  addCarouselCard(event) {
    event?.preventDefault()
    if (!this.hasCarouselCardListTarget || this.carouselCardRowTargets.length >= 10) return

    this.carouselCardListTarget.insertAdjacentHTML("beforeend", this.carouselCardTemplate(this.carouselCardRowTargets.length))
    this.refreshCarouselIndexes()
    this.toggleCarouselButtonRows()
  }

  removeCarouselCard(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='carouselCardRow']")
    if (!row) return

    if (this.carouselCardRowTargets.length <= 2) {
      row.querySelectorAll("input, textarea").forEach((input) => {
        if (input.type !== "hidden") input.value = ""
      })
      row.querySelectorAll("select").forEach((select) => {
        select.value = select.name.includes("[button_kind]") ? "url" : "image"
      })
      this.toggleCarouselButtonRows()
      return
    }

    row.remove()
    this.refreshCarouselIndexes()
    this.toggleCarouselButtonRows()
  }

  removeButton(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='buttonRow']")
    if (!row) return

    if (this.buttonRowTargets.length <= 1) {
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      row.querySelector("select").value = "quick_reply"
      this.toggleButtonRows()
      return
    }

    row.remove()
    this.refreshButtonIndexes()
    this.toggleButtonRows()
  }

  removeExample(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='exampleRow']")
    if (!row) return
    if (this.exampleRowTargets.length <= this.minimumExampleRows()) {
      const input = row.querySelector("input")
      if (input) input.value = ""
      return
    }

    row.remove()
    this.refreshExampleLabels()
  }

  toggleButtonRows() {
    this.element.querySelectorAll(".whatsapp-template-button-row").forEach((row) => {
      const select = row.querySelector("select")
      const extra = row.querySelector("[data-whatsapp-template-button-extra]")
      if (!select || !extra) return

      const needsExtra = ["url", "phone_number"].includes(select.value)
      extra.hidden = !needsExtra
      const input = extra.querySelector("input")
      if (input) {
        input.placeholder = select.value === "phone_number" ? "5511999990000" : "https://..."
      }
    })
  }

  toggleCarouselButtonRows() {
    this.element.querySelectorAll(".whatsapp-template-carousel-card").forEach((row) => {
      const select = row.querySelector("select[name*='[button_kind]']")
      if (!select) return

      row.querySelectorAll("[data-whatsapp-template-carousel-extra]").forEach((extra) => {
        extra.hidden = extra.dataset.whatsappTemplateCarouselExtra !== select.value
      })
    })
  }

  async updateFileName(event) {
    const input = event.currentTarget
    const control = input.closest(".whatsapp-template-upload-control")
    const status = control?.querySelector("[data-whatsapp-template-file-status]")
    if (!status) return

    const files = Array.from(input.files || [])
    status.textContent = files.length > 0 ? files.map((file) => file.name).join(", ") : "Nenhum arquivo selecionado"
    await this.uploadMediaHandle(input, control, status)
  }

  submitStarted() {
    const submitButton = this.element.querySelector("button[type='submit']")
    if (!submitButton) return

    submitButton.disabled = true
    submitButton.innerHTML = '<i class="bi bi-arrow-repeat ax-ico"></i><span>Enviando para a Meta...</span>'
  }

  async uploadMediaHandle(input, control, status) {
    const file = input.files?.[0]
    if (!file || !this.hasUploadMediaUrlValue) return

    const hiddenInput = this.mediaHandleInputFor(input, control)
    if (hiddenInput) hiddenInput.value = ""

    const mediaType = this.mediaTypeFor(input)
    if (!mediaType) return

    const formData = new FormData()
    formData.append("file", file)
    formData.append("media_type", mediaType)

    status.textContent = "Validando mídia na Meta..."

    try {
      const response = await fetch(this.uploadMediaUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        },
        body: formData,
        credentials: "same-origin"
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok || !data.handle) {
        throw new Error(data.error || "Não foi possível validar a mídia na Meta.")
      }

      const handle = this.normalizeMediaHandle(data.handle)
      if (!handle) throw new Error("A Meta não retornou um handle válido para esta mídia.")

      if (hiddenInput) hiddenInput.value = handle
      status.textContent = `${file.name} · validada na Meta`
    } catch (error) {
      if (hiddenInput) hiddenInput.value = ""
      status.textContent = error.message || "Não foi possível validar a mídia na Meta."
    }
  }

  mediaTypeFor(input) {
    if (input.name.includes("[header_media_file]")) {
      return this.hasMediaSelectTarget ? this.mediaSelectTarget.value : null
    }

    const card = input.closest("[data-whatsapp-template-form-target='carouselCardRow']")
    return card?.querySelector("select[name*='[media_type]']")?.value || null
  }

  mediaHandleInputFor(input, control) {
    const field = control?.closest(".ax-field")
    if (input.name.includes("[header_media_file]")) {
      return field?.querySelector("input[name='whatsapp_template[header_media_handle]']")
    }

    return field?.querySelector("input[type='hidden'][name*='[media_handle]']")
  }

  normalizeMediaHandle(value) {
    return String(value || "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find((line) => line.length > 0) || ""
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  buttonRowTemplate(index) {
    return `
      <div class="whatsapp-template-button-row" data-whatsapp-template-form-target="buttonRow">
        <div class="ax-field">
          <label class="ax-label" for="whatsapp_template_buttons_${index}_kind">Tipo</label>
          <select name="whatsapp_template[buttons][${index}][kind]"
                  id="whatsapp_template_buttons_${index}_kind"
                  class="ax-control"
                  data-action="change->whatsapp-template-form#toggleButtonRows">
            <option value="quick_reply">Resposta rápida</option>
            <option value="url">URL</option>
            <option value="phone_number">Telefone</option>
          </select>
        </div>
        <div class="ax-field">
          <label class="ax-label" for="whatsapp_template_buttons_${index}_text">Texto do botão</label>
          <input type="text"
                 name="whatsapp_template[buttons][${index}][text]"
                 id="whatsapp_template_buttons_${index}_text"
                 class="ax-control"
                 placeholder="Ex: Ver ofertas">
        </div>
        <div class="ax-field" data-whatsapp-template-button-extra>
          <label class="ax-label" for="whatsapp_template_buttons_${index}_url">URL ou telefone</label>
          <input type="text"
                 name="whatsapp_template[buttons][${index}][url]"
                 id="whatsapp_template_buttons_${index}_url"
                 class="ax-control"
                 placeholder="https://... ou 5511999990000">
        </div>
        <button type="button"
                class="ax-btn ax-btn--sm whatsapp-template-button-row__remove"
                aria-label="Remover botão"
                data-action="whatsapp-template-form#removeButton">
          <i class="bi bi-trash"></i>
        </button>
      </div>
    `
  }

  carouselCardTemplate(index) {
    return `
      <div class="whatsapp-template-carousel-card" data-whatsapp-template-form-target="carouselCardRow">
        <div class="whatsapp-template-carousel-card__head">
          <strong>Card ${index + 1}</strong>
          <button type="button"
                  class="ax-btn ax-btn--sm whatsapp-template-button-row__remove"
                  aria-label="Remover card"
                  data-action="whatsapp-template-form#removeCarouselCard">
            <i class="bi bi-trash"></i>
          </button>
        </div>
        <div class="whatsapp-template-carousel-card__grid">
          <div class="ax-field">
            <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_media_type">Tipo de mídia</label>
            <select name="whatsapp_template[carousel_cards][${index}][media_type]"
                    id="whatsapp_template_carousel_cards_${index}_media_type"
                    class="ax-control">
              <option value="image">Imagem</option>
              <option value="video">Vídeo</option>
            </select>
          </div>
          <div class="ax-field">
            <label class="ax-field-label" for="whatsapp_template_carousel_card_media_files_${index}">
              <span class="ax-field-label__text">Mídia do card</span>
              <button type="button"
                      class="ax-field-label__info"
                      aria-label="Ajuda: Mídia do card"
                      data-controller="ax-tooltip"
                      data-ax-tooltip-text-value="Formatos aceitos: imagem JPG/PNG ou vídeo MP4/3GPP. O sistema envia o arquivo para a Meta e usa o handle retornado na aprovação.">
                <i class="bi bi-info-circle" aria-hidden="true"></i>
              </button>
            </label>
            <div class="ax-upload-control whatsapp-template-upload-control">
              <label class="ax-btn ax-btn--sm ax-upload-button" for="whatsapp_template_carousel_card_media_files_${index}">Selecionar mídia</label>
              <input type="file"
                     name="whatsapp_template[carousel_card_media_files][]"
                     id="whatsapp_template_carousel_card_media_files_${index}"
                     class="ax-file-upload__input whatsapp-template-file"
                     accept="image/png,image/jpeg,video/mp4,video/3gpp"
                     data-action="change->whatsapp-template-form#updateFileName">
              <span class="ax-upload-status" data-whatsapp-template-file-status>Nenhum arquivo selecionado</span>
            </div>
            <input type="hidden"
                   name="whatsapp_template[carousel_cards][${index}][media_handle]"
                   id="whatsapp_template_carousel_cards_${index}_media_handle">
          </div>
          <div class="ax-field">
            <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_button_kind">Tipo de botão</label>
            <select name="whatsapp_template[carousel_cards][${index}][button_kind]"
                    id="whatsapp_template_carousel_cards_${index}_button_kind"
                    class="ax-control"
                    data-action="change->whatsapp-template-form#toggleCarouselButtonRows">
              <option value="quick_reply">Resposta rápida</option>
              <option value="url" selected>URL</option>
              <option value="phone_number">Telefone</option>
            </select>
          </div>
          <div class="ax-field">
            <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_button_text">Texto do botão</label>
            <input type="text"
                   name="whatsapp_template[carousel_cards][${index}][button_text]"
                   id="whatsapp_template_carousel_cards_${index}_button_text"
                   class="ax-control"
                   placeholder="Ver detalhes">
          </div>
          <div class="ax-field whatsapp-template-carousel-card__wide">
            <div class="whatsapp-template-carousel-button-extra" data-whatsapp-template-carousel-extra="url">
              <div class="whatsapp-template-carousel-extra-grid">
                <div class="ax-field">
                  <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_button_url">URL</label>
                  <input type="text"
                         name="whatsapp_template[carousel_cards][${index}][button_url]"
                         id="whatsapp_template_carousel_cards_${index}_button_url"
                         class="ax-control"
                         placeholder="https://exemplo.com/promo">
                </div>
                <div class="ax-field">
                  <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_button_url_example">Exemplo da URL</label>
                  <input type="text"
                         name="whatsapp_template[carousel_cards][${index}][button_url_example]"
                         id="whatsapp_template_carousel_cards_${index}_button_url_example"
                         class="ax-control"
                         placeholder="https://exemplo.com/cliente123">
                </div>
              </div>
            </div>
            <div class="whatsapp-template-carousel-button-extra" data-whatsapp-template-carousel-extra="phone_number" hidden>
              <div class="ax-field">
                <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_button_phone_number">Telefone</label>
                <input type="text"
                       name="whatsapp_template[carousel_cards][${index}][button_phone_number]"
                       id="whatsapp_template_carousel_cards_${index}_button_phone_number"
                       class="ax-control"
                       placeholder="5511999990000">
              </div>
            </div>
          </div>
          <div class="ax-field whatsapp-template-carousel-card__wide">
            <label class="ax-label" for="whatsapp_template_carousel_cards_${index}_text">Texto do card</label>
            <textarea name="whatsapp_template[carousel_cards][${index}][text]"
                      id="whatsapp_template_carousel_cards_${index}_text"
                      class="ax-control"
                      rows="3"
                      maxlength="160"
                      placeholder="Resumo curto do imóvel, oferta ou opção."></textarea>
          </div>
        </div>
      </div>
    `
  }

  refreshButtonIndexes() {
    this.buttonRowTargets.forEach((row, index) => {
      row.querySelectorAll("label, input, select").forEach((element) => {
        if (element.htmlFor) element.htmlFor = element.htmlFor.replace(/buttons_\d+_/, `buttons_${index}_`)
        if (element.id) element.id = element.id.replace(/buttons_\d+_/, `buttons_${index}_`)
        if (element.name) element.name = element.name.replace(/buttons\]\[\d+\]/, `buttons][${index}]`)
      })
    })
  }

  refreshCarouselIndexes() {
    if (!this.hasCarouselCardListTarget) return

    this.carouselCardRowTargets.forEach((row, index) => {
      const title = row.querySelector(".whatsapp-template-carousel-card__head strong")
      if (title) title.textContent = `Card ${index + 1}`

      row.querySelectorAll("label, input, textarea, select").forEach((element) => {
        if (element.htmlFor) {
          element.htmlFor = element.htmlFor
            .replace(/carousel_cards_\d+_/, `carousel_cards_${index}_`)
            .replace(/carousel_card_media_files_\d+/, `carousel_card_media_files_${index}`)
        }
        if (element.id) {
          element.id = element.id
            .replace(/carousel_cards_\d+_/, `carousel_cards_${index}_`)
            .replace(/carousel_card_media_files_\d+/, `carousel_card_media_files_${index}`)
        }
        if (element.name) element.name = element.name.replace(/carousel_cards\]\[\d+\]/, `carousel_cards][${index}]`)
      })
    })
  }

  addExampleRow() {
    const index = this.exampleRowTargets.length
    this.examplesListTarget.insertAdjacentHTML("beforeend", this.exampleRowTemplate(index))
  }

  exampleRowTemplate(index) {
    const placeholder = index === 0 ? "Maria Silva" : ""
    return `
      <div class="ax-field whatsapp-template-example-row" data-whatsapp-template-form-target="exampleRow">
        <label class="ax-label" for="whatsapp_template_example_values_${index}">Exemplo ${index + 1}</label>
        <div class="whatsapp-template-example-row__input">
          <input type="text"
                 name="whatsapp_template[example_values][]"
                 id="whatsapp_template_example_values_${index}"
                 class="ax-control"
                 placeholder="${placeholder}"
                 data-whatsapp-template-form-target="exampleInput">
          <button type="button"
                  class="ax-btn ax-btn--sm whatsapp-template-example-row__remove"
                  aria-label="Remover exemplo"
                  data-action="whatsapp-template-form#removeExample">
            <i class="bi bi-trash"></i>
          </button>
        </div>
      </div>
    `
  }

  refreshExampleLabels() {
    this.exampleRowTargets.forEach((row, index) => {
      const label = row.querySelector("label")
      const input = row.querySelector("input")
      if (label) {
        label.textContent = `Exemplo ${index + 1}`
        label.setAttribute("for", `whatsapp_template_example_values_${index}`)
      }
      if (input) input.id = `whatsapp_template_example_values_${index}`
    })
  }

  expectedExampleCount() {
    if (!this.hasBodyInputTarget) return this.minimumExampleRows()

    const indexes = Array.from(this.bodyInputTarget.value.matchAll(/\{\{(\d+)\}\}/g)).map((match) => Number(match[1]))
    return Math.max(this.minimumExampleRows(), ...indexes.filter((index) => Number.isFinite(index)))
  }

  minimumExampleRows() {
    return 1
  }
}
