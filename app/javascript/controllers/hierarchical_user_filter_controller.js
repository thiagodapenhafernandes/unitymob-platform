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
    selectionInputId: String
  }

  connect() {
    this.userInteracted = false
    this.markUserInteracted = () => { this.userInteracted = true }
    this.element.addEventListener("pointerdown", this.markUserInteracted, { capture: true })
    this.element.addEventListener("keydown", this.markUserInteracted, { capture: true })

    this.users = this.normalizedUsers()
    this.childrenByManager = this.buildChildrenIndex()
    this.restoredValuesByProfile = this.restoredValuesFromInput()
    this.populateLevels({ preserveExisting: false })
    this.restoredValuesByProfile = null
    this.updateSelectionInput()
    this.updateTargetSelect()
  }

  disconnect() {
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
    const selectedUserId = this.deepestSelectedUserId() || this.lockedUserIdValue
    if (!selectedUserId) return this.users

    const allowedIds = new Set([String(selectedUserId), ...this.descendantIds(selectedUserId)])
    return this.users.filter((user) => allowedIds.has(user.id))
  }

  deepestSelectedUserId() {
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
    return this.users.reduce((index, user) => {
      if (!user.managerId) return index

      const managerId = String(user.managerId)
      if (!index.has(managerId)) index.set(managerId, [])
      index.get(managerId).push(user)
      return index
    }, new Map())
  }

  normalizedUsers() {
    return (this.hasUsersValue ? this.usersValue : []).map((user) => ({
      id: String(user.id),
      name: user.name || "",
      profileId: String(user.profile_id || user.profileId || ""),
      profileName: user.profile_name || user.profileName || "",
      managerId: user.manager_id || user.managerId ? String(user.manager_id || user.managerId) : null
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
