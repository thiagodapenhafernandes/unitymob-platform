import { Controller } from "@hotwired/stimulus"

const FRIENDLY_KEYS = new Set([
  "transaction_type",
  "finalidade",
  "category",
  "category[]",
  "tipo",
  "city",
  "city[]",
  "cidade",
  "characteristics",
  "characteristics[]"
])

const IGNORED_KEYS = new Set(["authenticity_token", "utf8", "commit"])

export default class extends Controller {
  submit(event) {
    if (this.element.method.toLowerCase() !== "get") return

    const action = new URL(this.element.action, window.location.origin)
    if (action.pathname !== "/imoveis") return

    const formData = new FormData(this.element)
    const transaction = this.transactionType(formData)
    const categories = this.valuesFor(formData, ["category[]", "category", "tipo"])
    const locations = this.valuesFor(formData, ["city[]", "city", "cidade"])
    const characteristics = this.valuesFor(formData, ["characteristics[]", "characteristics"])
    const query = this.queryParams(formData)
    const path = this.friendlyPath(transaction, categories, locations, characteristics)

    event.preventDefault()
    window.location.href = query.toString() ? `${path}?${query}` : path
  }

  transactionType(formData) {
    const value = (formData.get("transaction_type") || formData.get("finalidade") || "venda").toString().toLowerCase()
    return ["aluguel", "locacao", "locação", "alugar"].includes(value) ? "aluguel" : "venda"
  }

  valuesFor(formData, names) {
    return names.flatMap((name) => formData.getAll(name))
      .map((value) => value.toString().trim())
      .filter((value) => value.length > 0)
      .filter((value, index, values) => values.indexOf(value) === index)
  }

  queryParams(formData) {
    const query = new URLSearchParams()

    formData.forEach((value, key) => {
      const cleaned = value.toString().trim()
      if (cleaned.length === 0 || FRIENDLY_KEYS.has(key) || IGNORED_KEYS.has(key)) return

      query.append(key, cleaned)
    })

    return query
  }

  friendlyPath(transaction, categories, locations, characteristics) {
    const segments = ["/imoveis", transaction]
    const hasCharacteristics = characteristics.length > 0
    const hasLocations = locations.length > 0

    if (categories.length > 0 || hasLocations || hasCharacteristics) {
      segments.push(this.segmentFor(categories))
    }

    if (hasLocations || hasCharacteristics) {
      segments.push(this.segmentFor(locations))
    }

    if (hasCharacteristics) {
      segments.push(this.segmentFor(characteristics))
    }

    return segments.join("/")
  }

  segmentFor(values) {
    if (values.length === 0) return "todos"

    return values.map((value) => this.slugFor(value)).filter(Boolean).join("+") || "todos"
  }

  slugFor(value) {
    return value.toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
  }
}
