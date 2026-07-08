import { Controller } from "@hotwired/stimulus"

// Filtra usuários por hierarquia vertical em cascata.
// Reutilizável para filas, relatórios e telas onde o usuário só pode navegar
// do próprio nível vertical para baixo.
export default class extends Controller {
  static targets = ["levelSelect"]
  static values = {
    users: Array,
    lockedUserId: String,
    targetSelectId: String,
    selectionInputId: String,
    mode: { type: String, default: "single" },
    area: { type: String, default: "" },
    selectedIds: { type: Array, default: [] }
  }

  get multi() {
    return this.modeValue === "multi"
  }

  connect() {
    this.handleAreaBroadcast = (event) => {
      this.areaValue = String(event.detail?.value || "")
      this.childrenByManager = this.buildChildrenIndex()
      this.populateLevels()
      this.updateSelectionInput()
      this.updateTargetSelect()
      this.dispatch("change", { detail: { userIds: this.filteredTargetUsers().map((user) => user.id), selectedUserId: null } })
    }
    window.addEventListener("distribution:area", this.handleAreaBroadcast)
    this.userInteracted = false
    this.markUserInteracted = () => { this.userInteracted = true }
    this.element.addEventListener("pointerdown", this.markUserInteracted, { capture: true })
    this.element.addEventListener("keydown", this.markUserInteracted, { capture: true })

    this.users = this.normalizedUsers()
    this.childrenByManager = this.buildChildrenIndex()
    this.restoredValuesByProfile = this.restoredValuesFromInput()
    this.restoredMultiIds = new Set((this.hasSelectedIdsValue ? this.selectedIdsValue : []).map(String))
    this.populateLevels({ preserveExisting: false })
    this.restoredValuesByProfile = null
    this.restoredMultiIds = null
    this.updateSelectionInput()
    this.updateTargetSelect()
  }

  disconnect() {
    window.removeEventListener("distribution:area", this.handleAreaBroadcast)
    this.element.removeEventListener("pointerdown", this.markUserInteracted, { capture: true })
    this.element.removeEventListener("keydown", this.markUserInteracted, { capture: true })
  }

  filter(eventOrOptions = {}) {
    const calledByEvent = eventOrOptions instanceof Event
    const notify = calledByEvent ? this.userInteracted : eventOrOptions.notify !== false

    this.populateLevels()
    this.updateSelectionInput()
    this.updateTargetSelect()
    if (!notify) return

    this.dispatch("change", {
      detail: {
        userIds: this.filteredTargetUsers().map((user) => user.id),
        selectedUserId: this.deepestSelectedUserId() || this.lockedUserIdValue || null
      }
    })
  }

  populateLevels({ preserveExisting = true } = {}) {
    if (this.multi) {
      this.populateLevelsMulti({ preserveExisting })
      return
    }

    let selectedAncestorId = null
    let cascadeOpen = !this.lockedUserIdValue

    this.levelSelectTargets.forEach((select, index) => {
      const profileId = String(select.dataset.profileId || "")
      const previousValue = this.restoredValuesByProfile?.get(profileId) || (preserveExisting ? this.selectValue(select) : "")
      const lockedAtThisLevel = this.lockedUser && String(this.lockedUser.profileId) === profileId
      const enabledAtThisLevel = lockedAtThisLevel || cascadeOpen || (index === 0 && !this.lockedUserIdValue)
      const ancestorForThisLevel = lockedAtThisLevel ? null : selectedAncestorId
      const options = enabledAtThisLevel ? this.usersForProfile(profileId, ancestorForThisLevel) : []

      this.replaceSelectOptions(select, options, lockedAtThisLevel, enabledAtThisLevel)

      if (lockedAtThisLevel) {
        this.setSelectValue(select, this.lockedUser.id)
        select.disabled = true
        select.tomselect?.disable()
        selectedAncestorId = this.lockedUser.id
        cascadeOpen = true
      } else if (previousValue && options.some((user) => user.id === previousValue)) {
        this.setSelectValue(select, previousValue)
        select.disabled = false
        select.tomselect?.enable()
        selectedAncestorId = previousValue
        cascadeOpen = true
      } else if (enabledAtThisLevel) {
        this.setSelectValue(select, "")
        select.disabled = false
        select.tomselect?.enable()
        cascadeOpen = false
      } else {
        this.setSelectValue(select, "")
        select.disabled = true
        select.tomselect?.disable()
      }
    })
  }

  // Modo multi (fila de distribuição): cada nível é multi-select SEM "Todos";
  // a seleção acima filtra as opções abaixo e a união define os subordinados.
  populateLevelsMulti({ preserveExisting = true } = {}) {
    let unionAbove = null // null = nenhum filtro herdado (primeiro nível mostra o perfil inteiro)

    this.levelSelectTargets.forEach((select) => {
      const profileId = String(select.dataset.profileId || "")
      const restored = !preserveExisting && this.restoredMultiIds ? [...this.restoredMultiIds] : null
      const previous = preserveExisting ? this.selectValues(select) : (restored || [])
      const lockedAtThisLevel = this.lockedUser && String(this.lockedUser.profileId) === profileId

      // Gestores também respeitam a área da regra (venda/locação/ambos) —
      // nunca engessar: o dataset vem completo e o corte é dinâmico aqui.
      let options = this.users.filter((user) => String(user.profileId) === profileId && this.actingMatchesArea(user))
      if (unionAbove) options = options.filter((user) => unionAbove.has(user.id))
      options.sort((a, b) => a.name.localeCompare(b.name, "pt-BR"))

      this.replaceMultiOptions(select, options)

      let kept
      if (lockedAtThisLevel) {
        kept = [this.lockedUser.id]
        this.setMultiValue(select, kept)
        select.disabled = true
        select.tomselect?.disable()
      } else {
        kept = previous.filter((value) => options.some((user) => user.id === value))
        this.setMultiValue(select, kept)
        select.disabled = false
        select.tomselect?.enable()
      }

      if (kept.length > 0) {
        const allowed = new Set()
        kept.forEach((id) => {
          allowed.add(String(id))
          this.descendantIds(id).forEach((descendantId) => allowed.add(descendantId))
        })
        unionAbove = allowed
      }
    })
  }

  replaceMultiOptions(select, users) {
    if (select.tomselect) {
      select.tomselect.clearOptions()
      users.forEach((user) => select.tomselect.addOption({ value: user.id, text: user.name }))
      select.tomselect.refreshOptions(false)
      return
    }

    const previous = new Set(this.selectValues(select))
    select.innerHTML = ""
    users.forEach((user) => select.add(new Option(user.name, user.id, previous.has(user.id), previous.has(user.id))))
  }

  setMultiValue(select, values) {
    if (select.tomselect) {
      select.tomselect.setValue(values, true)
      return
    }

    Array.from(select.options).forEach((option) => { option.selected = values.includes(String(option.value)) })
  }

  selectValues(select) {
    if (select.tomselect) return [].concat(select.tomselect.getValue() || []).map(String).filter(Boolean)

    return Array.from(select.selectedOptions || []).map((option) => String(option.value)).filter(Boolean)
  }

  allSelectedIds() {
    return this.levelSelectTargets.flatMap((select) => this.selectValues(select))
  }

  updateTargetSelect() {
    const target = this.targetSelect
    if (!target) return

    const filteredUsers = this.filteredTargetUsers()
    const selectedIds = this.selectedTargetIds(target)
    const usersById = new Map(this.users.map((user) => [user.id, user]))
    const selectedUsers = selectedIds.map((id) => usersById.get(id)).filter(Boolean)
    const optionUsers = this.uniqueUsers([...filteredUsers, ...selectedUsers])

    if (target.tomselect) {
      target.tomselect.clearOptions()
      optionUsers.forEach((user) => target.tomselect.addOption({ value: user.id, text: user.name }))
      target.tomselect.refreshOptions(false)
      return
    }

    const selected = new Set(selectedIds)
    target.innerHTML = ""
    optionUsers.forEach((user) => {
      const option = new Option(user.name, user.id, selected.has(user.id), selected.has(user.id))
      target.add(option)
    })
  }

  updateSelectionInput() {
    const input = this.selectionInput
    if (!input) return

    input.value = this.deepestSelectedUserId() || this.lockedUserIdValue || ""
  }

  restoredValuesFromInput() {
    const input = this.selectionInput
    const selectedId = input?.value || ""
    if (!selectedId) return new Map()

    const selectedUser = this.users.find((user) => user.id === String(selectedId))
    if (!selectedUser) {
      input.value = ""
      return new Map()
    }

    return this.ancestorChain(selectedUser).reduce((values, user) => {
      values.set(user.profileId, user.id)
      return values
    }, new Map())
  }

  filteredTargetUsers() {
    if (this.multi) {
      // união das equipes dos gestores selecionados; sem seleção = vazio
      const selectedIds = this.allSelectedIds()
      if (selectedIds.length === 0) return []

      const allowedIds = new Set()
      selectedIds.forEach((id) => {
        allowedIds.add(String(id))
        this.descendantIds(id).forEach((descendantId) => allowedIds.add(descendantId))
      })
      return this.users.filter((user) => allowedIds.has(user.id) && this.actingMatchesArea(user))
    }

    const selectedUserId = this.deepestSelectedUserId() || this.lockedUserIdValue
    if (!selectedUserId) return this.users

    const allowedIds = new Set([String(selectedUserId), ...this.descendantIds(selectedUserId)])
    return this.users.filter((user) => allowedIds.has(user.id))
  }

  actingMatchesArea(user) {
    const area = this.hasAreaValue ? this.areaValue : ""
    if (area === "venda") return user.actingType === "sales" || user.actingType === "both"
    if (area === "locacao") return user.actingType === "rentals" || user.actingType === "both"
    return true
  }

  deepestSelectedUserId() {
    if (this.multi) return this.allSelectedIds().pop() || ""

    return this.levelSelectTargets.map((select) => select.value).filter(Boolean).pop()
  }

  usersForProfile(profileId, ancestorId) {
    let users = this.users.filter((user) => String(user.profileId) === String(profileId))
    if (ancestorId) {
      const allowedIds = new Set([String(ancestorId), ...this.descendantIds(ancestorId)])
      users = users.filter((user) => allowedIds.has(user.id))
    }

    return users.sort((a, b) => a.name.localeCompare(b.name, "pt-BR"))
  }

  replaceSelectOptions(select, users, lockedAtThisLevel, enabledAtThisLevel = true) {
    const blankLabel = enabledAtThisLevel ? "Todos" : "Selecione acima"

    if (select.tomselect) {
      select.tomselect.clearOptions()
      if (!lockedAtThisLevel) select.tomselect.addOption({ value: "", text: blankLabel })
      users.forEach((user) => select.tomselect.addOption({ value: user.id, text: user.name }))
      select.tomselect.refreshOptions(false)
      return
    }

    select.innerHTML = ""
    if (!lockedAtThisLevel) select.add(new Option(blankLabel, ""))
    users.forEach((user) => select.add(new Option(user.name, user.id)))
  }

  selectValue(select) {
    if (select.tomselect) return String(select.tomselect.getValue() || "")
    return String(select.value || "")
  }

  setSelectValue(select, value) {
    const normalizedValue = String(value || "")
    if (select.tomselect) {
      select.tomselect.setValue(normalizedValue, true)
      return
    }

    select.value = normalizedValue
  }

  descendantIds(userId) {
    const ids = []
    const stack = [...(this.childrenByManager.get(String(userId)) || [])]

    while (stack.length > 0) {
      const child = stack.shift()
      ids.push(child.id)
      stack.push(...(this.childrenByManager.get(child.id) || []))
    }

    return ids
  }

  ancestorChain(user) {
    const usersById = new Map(this.users.map((candidate) => [candidate.id, candidate]))
    const chain = []
    let cursor = user

    while (cursor) {
      chain.unshift(cursor)
      cursor = cursor.managerId ? usersById.get(cursor.managerId) : null
    }

    return chain
  }

  buildChildrenIndex() {
    const area = this.hasAreaValue ? this.areaValue : ""
    return this.users.reduce((index, user) => {
      const links = []
      if (area !== "locacao" && user.managerId) links.push(user.managerId)
      if (area !== "venda" && user.rentalsManagerId) links.push(user.rentalsManagerId)

      new Set(links.map(String)).forEach((managerId) => {
        if (!index.has(managerId)) index.set(managerId, [])
        index.get(managerId).push(user)
      })
      return index
    }, new Map())
  }

  normalizedUsers() {
    return (this.hasUsersValue ? this.usersValue : []).map((user) => ({
      id: String(user.id),
      name: user.name || "",
      profileId: String(user.profile_id || user.profileId || ""),
      profileName: user.profile_name || user.profileName || "",
      managerId: user.manager_id || user.managerId ? String(user.manager_id || user.managerId) : null,
      rentalsManagerId: user.rentals_manager_id || user.rentalsManagerId ? String(user.rentals_manager_id || user.rentalsManagerId) : null,
      actingType: user.acting_type || user.actingType || ""
    })).filter((user) => user.id && user.profileId)
  }

  selectedTargetIds(target) {
    if (target.tomselect) return target.tomselect.getValue().map(String).filter(Boolean)

    return Array.from(target.selectedOptions || []).map((option) => String(option.value)).filter(Boolean)
  }

  uniqueUsers(users) {
    return Array.from(users.reduce((map, user) => {
      if (user?.id && !map.has(user.id)) map.set(user.id, user)
      return map
    }, new Map()).values())
  }

  get targetSelect() {
    if (!this.targetSelectIdValue) return null
    return document.getElementById(this.targetSelectIdValue)
  }

  get selectionInput() {
    if (!this.selectionInputIdValue) return null
    return document.getElementById(this.selectionInputIdValue)
  }

  get lockedUser() {
    if (!this.lockedUserIdValue) return null
    return this.users.find((user) => user.id === String(this.lockedUserIdValue))
  }
}
