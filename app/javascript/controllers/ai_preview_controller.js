import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async submit(event) {
    event.preventDefault()

    const button = event.currentTarget
    const confirmMessage = button.dataset.aiPreviewConfirmMessage
    if (confirmMessage && !window.confirm(confirmMessage)) return

    const originalHtml = button.innerHTML
    const loadingFields = this.aiEditableFields()
    this.setLoading(button)
    this.setFieldsLoading(loadingFields, true)

    try {
      const response = await fetch(button.href, {
        method: button.dataset.aiPreviewMethod || "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "text/html",
          "Turbo-Frame": button.dataset.turboFrame || "",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })
      const html = await response.text()

      this.replaceFrame(button.dataset.turboFrame, html)
      this.fillEditableFields(button.dataset.turboFrame)

      if (!response.ok) throw new Error(`AI preview request failed with status ${response.status}`)
    } catch (error) {
      console.error(error)
      window.alert("Não foi possível processar a ação da IA.")
    } finally {
      button.innerHTML = originalHtml
      button.classList.remove("disabled")
      button.removeAttribute("aria-disabled")
      this.setFieldsLoading(loadingFields, false)
    }
  }

  loading(event) {
    const button = event.currentTarget
    this.setLoading(button)
  }

  setLoading(button) {
    const loadingText = button.dataset.aiPreviewLoadingText || "Processando..."

    button.classList.add("disabled")
    button.setAttribute("aria-disabled", "true")
    button.innerHTML = `
      <span class="spinner-border spinner-border-sm me-1" aria-hidden="true"></span>
      ${loadingText}
    `
  }

  replaceFrame(frameId, html) {
    if (!frameId) return

    const frame = document.getElementById(frameId)
    if (!frame) return

    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const responseFrame = template.content.querySelector(`turbo-frame#${CSS.escape(frameId)}`)

    if (responseFrame) {
      frame.replaceWith(responseFrame)
    } else {
      frame.innerHTML = html
    }
  }

  fillEditableFields(frameId) {
    const frame = frameId ? document.getElementById(frameId) : document
    const payload = frame?.querySelector("[data-ai-preview-fill-title], [data-ai-preview-fill-description-html]")
    if (!payload) return

    this.fillInput("habitation[titulo_anuncio]", payload.dataset.aiPreviewFillTitle)
    this.fillRichText("habitation[descricao_web]", payload.dataset.aiPreviewFillDescriptionHtml)
    this.fillInput("habitation[meta_title]", payload.dataset.aiPreviewFillTitle)
    this.fillRichText("habitation[meta_description]", payload.dataset.aiPreviewFillDescriptionHtml)
    this.fillTags("habitation[meta_keywords]", payload.dataset.aiPreviewFillSeoKeywords)
  }

  fillInput(name, value) {
    if (value == null) return

    const input = document.querySelector(`[name="${CSS.escape(name)}"]`)
    if (!input || input.readOnly || input.disabled) return

    input.value = value
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  fillRichText(name, html) {
    if (html == null) return

    const input = document.querySelector(`[name="${CSS.escape(name)}"]`)
    if (!input || input.disabled) return

    const editor = document.querySelector(`trix-editor[input="${CSS.escape(input.id)}"]`)
    if (editor?.editor) {
      editor.editor.loadHTML(html)
      editor.dispatchEvent(new Event("input", { bubbles: true }))
      editor.dispatchEvent(new Event("change", { bubbles: true }))
      return
    }

    input.value = html
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  fillTags(name, value) {
    if (value == null) return

    const input = document.querySelector(`[name="${CSS.escape(name)}"]`)
    if (!input || input.readOnly || input.disabled) return

    const tags = value.split(",").map((tag) => tag.trim()).filter(Boolean)
    if (input.tomselect) {
      input.tomselect.clear()
      tags.forEach((tag) => {
        input.tomselect.addOption({ value: tag, text: tag })
        input.tomselect.addItem(tag, true)
      })
      input.tomselect.refreshOptions(false)
      input.tomselect.refreshItems()
    }

    input.value = tags.join(", ")
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  aiEditableFields() {
    return [
      this.fieldElementsFor("habitation[titulo_anuncio]"),
      this.fieldElementsFor("habitation[descricao_web]"),
      this.fieldElementsFor("habitation[meta_title]"),
      this.fieldElementsFor("habitation[meta_description]"),
      this.fieldElementsFor("habitation[meta_keywords]")
    ].flat()
  }

  fieldElementsFor(name) {
    const input = document.querySelector(`[name="${CSS.escape(name)}"]`)
    if (!input) return []

    const elements = [input]
    const editor = input.id ? document.querySelector(`trix-editor[input="${CSS.escape(input.id)}"]`) : null
    if (editor) elements.push(editor)

    const wrapper = (editor || input).closest(".ax-field-group, .ax-field, .trix-content")
    if (wrapper) elements.push(wrapper)

    return elements
  }

  setFieldsLoading(elements, loading) {
    const uniqueElements = [...new Set(elements.filter(Boolean))]
    uniqueElements.forEach((element) => {
      element.classList.toggle("is-ai-loading", loading)
      if (loading) {
        element.setAttribute("aria-busy", "true")
      } else {
        element.removeAttribute("aria-busy")
      }
    })
  }
}
