const LEGACY_FAVORITES_KEY = "salute:favorite-properties"
const FAVORITES_EVENT = "unitymob:favorites-changed"

function tenantSlug() {
  return document.body?.dataset?.publicTenantSlug || "default"
}

export function favoritesStorageKey() {
  const slug = tenantSlug().trim() || "default"

  return `unitymob:${slug}:favorite-properties`
}

export function legacyFavoritesStorageKey() {
  return LEGACY_FAVORITES_KEY
}

export function readFavorites() {
  try {
    const currentValue = localStorage.getItem(favoritesStorageKey())
    if (currentValue !== null) {
      const current = JSON.parse(currentValue || "[]")
      return Array.isArray(current) ? current : []
    }

    if (tenantSlug() === "default") {
      const legacy = JSON.parse(localStorage.getItem(legacyFavoritesStorageKey()) || "[]")
      return Array.isArray(legacy) ? legacy : []
    }

    return Array.isArray(current) ? current : []
  } catch (_error) {
    return []
  }
}

export function writeFavorites(favorites) {
  localStorage.setItem(favoritesStorageKey(), JSON.stringify(favorites))
  if (tenantSlug() === "default") {
    localStorage.setItem(legacyFavoritesStorageKey(), JSON.stringify(favorites))
  }
}

export function clearFavorites() {
  localStorage.removeItem(favoritesStorageKey())
  if (tenantSlug() === "default") localStorage.removeItem(legacyFavoritesStorageKey())
}

export function dispatchFavoritesChanged() {
  window.dispatchEvent(new CustomEvent(FAVORITES_EVENT))
  window.dispatchEvent(new CustomEvent("salute:favorites-changed"))
}

export function onFavoritesChanged(callback) {
  window.addEventListener(FAVORITES_EVENT, callback)
  window.addEventListener("salute:favorites-changed", callback)
}

export function offFavoritesChanged(callback) {
  window.removeEventListener(FAVORITES_EVENT, callback)
  window.removeEventListener("salute:favorites-changed", callback)
}
