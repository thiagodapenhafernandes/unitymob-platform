import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "code",
    "name",
    "phone",
    "cpfCnpj",
    "email",
    "city",
    "proprietorId",
    "matchBox",
    "matchTitle",
    "matchDescription",
    "linkedBox",
    "linkedDescription"
  ]

  static values = { url: String }

  connect() {
    this.lookupTimer = null
    this.pendingMatch = null
    this.appliedFingerprint = this.currentFingerprint()
    this.syncLinkedState()
  }

  disconnect() {
    clearTimeout(this.lookupTimer)
  }

  lookup() {
    clearTimeout(this.lookupTimer)
    this.lookupTimer = setTimeout(() => this.performLookup(), 250)
  }

  async performLookup() {
    if (!this.hasUrlValue) return

    const code = this.codeValue
    const phone = this.phoneValue
    const cpfCnpj = this.cpfCnpjValue
    const email = this.emailValue

    if (!this.lookupReady(code, phone, cpfCnpj, email)) {
      this.pendingMatch = null
      if (!this.selectedProprietor()) this.hideMatch()
      return
    }

    const params = new URLSearchParams()

    if (this.validCode(code)) params.set("code", code)
    if (this.normalizedPhone(phone).length >= 8) params.set("phone", phone)
    if (this.validDocument(cpfCnpj)) params.set("cpf_cnpj", cpfCnpj)
    if (this.validEmail(email)) params.set("email", email)

    try {
      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) return

      const data = await response.json()

      if (!data.found) {
        this.pendingMatch = null
        if (!this.selectedProprietor()) this.hideMatch()
        return
      }

      this.pendingMatch = data

      if (this.selectedProprietor() && String(this.proprietorIdTarget.value) === String(data.proprietor.id)) {
        this.showLinked(data.proprietor)
        this.hideMatch()
        return
      }

      this.showMatch(data)
    } catch (_error) {
      // Lookup failure should not block the form.
    }
  }

  applyMatch() {
    const proprietor = this.pendingMatch?.proprietor
    if (!proprietor) return

    this.proprietorIdTarget.value = proprietor.id || ""
    if (this.hasCodeTarget && proprietor.code) this.codeTarget.value = proprietor.code
    if (this.hasNameTarget && proprietor.name) this.nameTarget.value = proprietor.name
    if (this.hasPhoneTarget && proprietor.phone) this.phoneTarget.value = proprietor.phone
    if (this.hasCpfCnpjTarget && proprietor.cpf_cnpj) this.cpfCnpjTarget.value = proprietor.cpf_cnpj
    if (this.hasEmailTarget && proprietor.email) this.emailTarget.value = proprietor.email
    if (this.hasCityTarget && proprietor.city) this.cityTarget.value = proprietor.city

    this.appliedFingerprint = this.currentFingerprint()
    this.hideMatch()
    this.showLinked(proprietor)
  }

  dismissMatch() {
    this.pendingMatch = null
    this.hideMatch()
  }

  handleManualEdit() {
    if (!this.selectedProprietor()) return
    if (this.currentFingerprint() === this.appliedFingerprint) return

    this.proprietorIdTarget.value = ""
    this.pendingMatch = null
    this.hideLinked()
  }

  syncLinkedState() {
    if (!this.selectedProprietor()) {
      this.hideLinked()
      return
    }

    this.showLinked({
      label: this.currentLinkedLabel(),
      name: this.nameValue,
      phone: this.phoneValue,
      email: this.emailValue
    })
  }

  showMatch(data) {
    if (!this.hasMatchBoxTarget) return

    const proprietor = data.proprietor || {}
    this.matchTitleTarget.textContent = "Proprietário já cadastrado"
    this.matchDescriptionTarget.textContent = `${this.matchLabel(proprietor)} encontrado pelo ${this.matchedByLabel(data.matched_by)} informado.`
    this.matchBoxTarget.classList.remove("tw-hidden")
  }

  hideMatch() {
    if (!this.hasMatchBoxTarget) return

    this.matchBoxTarget.classList.add("tw-hidden")
  }

  showLinked(proprietor) {
    if (!this.hasLinkedBoxTarget) return

    this.linkedDescriptionTarget.textContent = `Os dados desta captação estão vinculados a ${this.matchLabel(proprietor)}. Se você alterar os campos abaixo, o vínculo é removido para evitar sobrescrever o cadastro existente.`
    this.linkedBoxTarget.classList.remove("tw-hidden")
  }

  hideLinked() {
    if (!this.hasLinkedBoxTarget) return

    this.linkedBoxTarget.classList.add("tw-hidden")
  }

  selectedProprietor() {
    return this.hasProprietorIdTarget && this.proprietorIdTarget.value.trim() !== ""
  }

  lookupReady(code, phone, cpfCnpj, email) {
    return this.validCode(code) || this.normalizedPhone(phone).length >= 8 || this.validDocument(cpfCnpj) || this.validEmail(email)
  }

  validCode(value) {
    return (value || "").trim().length > 0
  }

  validDocument(value) {
    const digits = this.onlyDigits(value)
    return digits.length === 11 || digits.length === 14
  }

  validEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test((value || "").trim().toLowerCase())
  }

  normalizedPhone(value) {
    return this.onlyDigits(value)
  }

  onlyDigits(value) {
    return (value || "").replace(/\D/g, "")
  }

  currentFingerprint() {
    return [
      (this.codeValue || "").trim().toLowerCase(),
      (this.nameValue || "").trim().toLowerCase(),
      this.normalizedPhone(this.phoneValue),
      this.onlyDigits(this.cpfCnpjValue),
      (this.emailValue || "").trim().toLowerCase(),
      (this.cityValue || "").trim().toLowerCase()
    ].join("|")
  }

  currentLinkedLabel() {
    const name = this.nameValue?.trim()
    const phone = this.phoneValue?.trim()
    const email = this.emailValue?.trim()
    return [name, phone, email].filter(Boolean).join(" · ")
  }

  matchLabel(proprietor) {
    return proprietor.label || proprietor.name || "um proprietário existente"
  }

  matchedByLabel(value) {
    switch (value) {
      case "phone":
        return "telefone"
      case "cpf_cnpj":
        return "CPF ou CNPJ"
      case "email":
        return "e-mail"
      case "code":
        return "código"
      default:
        return "dado"
    }
  }

  get codeValue() {
    return this.hasCodeTarget ? this.codeTarget.value : ""
  }

  get nameValue() {
    return this.hasNameTarget ? this.nameTarget.value : ""
  }

  get phoneValue() {
    return this.hasPhoneTarget ? this.phoneTarget.value : ""
  }

  get cpfCnpjValue() {
    return this.hasCpfCnpjTarget ? this.cpfCnpjTarget.value : ""
  }

  get emailValue() {
    return this.hasEmailTarget ? this.emailTarget.value : ""
  }

  get cityValue() {
    return this.hasCityTarget ? this.cityTarget.value : ""
  }
}
