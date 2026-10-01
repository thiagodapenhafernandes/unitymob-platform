import { Controller } from "@hotwired/stimulus"

// Combobox multi-seleção dos filtros públicos (hero luxury e drawer de filtro
// de todos os temas). Marcação: .public-theme-combobox > input[type=hidden] +
// __trigger (__tags + __input) + __panel (__option[data-value] > __label).
export default class extends Controller {
  // single: escolha única (a nova seleção troca a anterior e o painel fecha), usada onde o parâmetro não é uma lista (ex.: dormitórios).
  static values = { compact: Boolean, single: Boolean }

  connect() {
    const combobox = this.element
    const hidden = combobox.querySelector("input[type='hidden']")
    const trigger = combobox.querySelector(".public-theme-combobox__trigger")
    const tags = combobox.querySelector(".public-theme-combobox__tags")
    const input = combobox.querySelector(".public-theme-combobox__input")
    const panel = combobox.querySelector(".public-theme-combobox__panel")
    const empty = combobox.querySelector(".public-theme-combobox__empty")
    const options = Array.from(panel.querySelectorAll(".public-theme-combobox__option"))
    const placeholder = input.getAttribute("placeholder") || ""
    const compactSelection = this.compactValue
    const single = this.singleValue
    const selected = new Map()

    options.forEach((option) => {
      option.dataset.raw = option.querySelector(".public-theme-combobox__label").textContent
      if (!option.querySelector(".public-theme-combobox__check")) option.insertAdjacentHTML("beforeend", '<i class="public-theme-combobox__check bi bi-check2" aria-hidden="true"></i>')
    })

    const visible = () => options.filter((option) => option.style.display !== "none")
    const clearActive = () => options.forEach((option) => option.classList.remove("active"))
    const setActive = (option) => {
      clearActive()
      if (!option) return

      option.classList.add("active")
      option.scrollIntoView({ block: "nearest" })
    }
    const open = () => {
      if (combobox.classList.contains("open")) return

      document.querySelectorAll(".public-theme-combobox.open").forEach((openCombobox) => {
        if (openCombobox !== combobox) openCombobox.classList.remove("open")
      })
      combobox.classList.add("open")
      trigger.setAttribute("aria-expanded", "true")
      // Sem destaque ao abrir: ele só aparece ao navegar pelo teclado ou
      // digitar, para não parecer um estado diferente dos selecionados.
    }
    const close = () => {
      combobox.classList.remove("open")
      trigger.setAttribute("aria-expanded", "false")
      clearActive()
    }
    const filter = () => {
      const query = this.normalize(input.value)
      let any = false

      options.forEach((option) => {
        const raw = option.dataset.raw || ""
        const show = !query || this.normalize(option.dataset.search || raw).includes(query)
        option.style.display = show ? "" : "none"
        if (show) any = true
        option.querySelector(".public-theme-combobox__label").textContent = raw
      })

      if (empty) empty.hidden = any
    }
    const sync = () => {
      this.writeComboboxValues(hidden, Array.from(selected.keys()))
      tags.innerHTML = ""
      const entries = Array.from(selected.entries())
      const appendTag = (value, label) => {
        const tag = document.createElement("span")
        tag.className = "public-theme-combobox__tag"
        tag.innerHTML = '<span class="public-theme-combobox__tag-label"></span><button type="button" class="public-theme-combobox__tag-remove" aria-label="Remover">&times;</button>'
        tag.querySelector(".public-theme-combobox__tag-label").textContent = label
        tag.querySelector(".public-theme-combobox__tag-remove").addEventListener("mousedown", (event) => {
          event.preventDefault()
          event.stopPropagation()
          toggle(value, label)
        })
        tags.appendChild(tag)
      }

      if (compactSelection && entries.length > 1) {
        const [value, label] = entries[0]
        appendTag(value, label)

        const count = document.createElement("span")
        count.className = "public-theme-combobox__count"
        count.textContent = entries.length
        count.setAttribute("aria-label", `${entries.length} itens selecionados`)
        tags.appendChild(count)
      } else {
        entries.forEach(([value, label]) => appendTag(value, label))
      }
      input.placeholder = selected.size ? "" : placeholder
    }
    const toggle = (value, label) => {
      const option = options.find((candidate) => candidate.dataset.value === value)
      if (selected.has(value)) {
        selected.delete(value)
        if (option) option.classList.remove("selected")
      } else {
        if (single) {
          selected.clear()
          options.forEach((candidate) => candidate.classList.remove("selected"))
        }
        selected.set(value, label)
        if (option) option.classList.add("selected")
      }
      sync()
    }
    const pick = (option) => {
      toggle(option.dataset.value, option.dataset.raw)
      input.value = ""
      filter()
      if (single) {
        close()
        input.blur()
      } else {
        input.focus()
      }
    }

    options.forEach((option) => {
      option.addEventListener("mousedown", (event) => {
        event.preventDefault()
        pick(option)
      })
    })
    input.addEventListener("input", () => {
      open()
      filter()
      setActive(visible()[0])
    })
    input.addEventListener("focus", open)
    trigger.addEventListener("click", (event) => {
      if (event.target.closest(".public-theme-combobox__tag")) return
      input.focus()
      open()
    })
    combobox.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        if (!combobox.classList.contains("open")) {
          open()
          return
        }
        const candidates = visible()
        if (!candidates.length) return
        let index = candidates.findIndex((option) => option.classList.contains("active"))
        index = event.key === "ArrowDown" ? (index + 1) % candidates.length : (index - 1 + candidates.length) % candidates.length
        setActive(candidates[index])
      } else if (event.key === "Enter") {
        event.preventDefault()
        const active = panel.querySelector(".public-theme-combobox__option.active")
        if (combobox.classList.contains("open") && active && active.style.display !== "none") pick(active)
      } else if (event.key === "Escape") {
        close()
        input.blur()
      } else if ((event.key === "Backspace" || event.key === "Delete") && input.value === "" && selected.size) {
        // Campo vazio: apaga a última seleção, como num campo de tags comum.
        event.preventDefault()
        const [value, label] = Array.from(selected.entries()).pop()
        toggle(value, label)
      }
    })


    this.resetSelection = () => {
      selected.clear()
      options.forEach((option) => option.classList.remove("selected"))
      input.value = ""
      sync()
      filter()
      close()
    }
    this.closeOutside = (event) => {
      if (!combobox.contains(event.target)) close()
    }
    this.form = combobox.closest("form")
    this.form?.addEventListener("reset", this.resetSelection)
    document.addEventListener("click", this.closeOutside)

    sync()
    filter()
  }

  disconnect() {
    this.form?.removeEventListener("reset", this.resetSelection)
    document.removeEventListener("click", this.closeOutside)
  }

  // Campos array (category[], city[]) mandam um input por valor — a busca não
  // separa "A, B" dentro de um item só. Campos simples seguem juntando por vírgula.
  writeComboboxValues(hidden, values) {
    if (!hidden.name.endsWith("[]")) {
      hidden.value = values.join(", ")
      return
    }

    hidden.parentElement.querySelectorAll(":scope > input[data-combobox-extra]").forEach((input) => input.remove())
    hidden.value = values[0] || ""
    values.slice(1).reverse().forEach((value) => {
      const extra = document.createElement("input")
      extra.type = "hidden"
      extra.name = hidden.name
      extra.value = value
      extra.dataset.comboboxExtra = ""
      hidden.after(extra)
    })
  }

  normalize(value) {
    return (value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
  }
}
