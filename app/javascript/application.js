// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "submit_guard"
import "pwa_scope_guard"
import "controllers"
import "ax_toast"

let actionTextLoadPromise = null

const loadActionText = () => {
  if (actionTextLoadPromise) return actionTextLoadPromise

  actionTextLoadPromise = import("trix")
    .then(() => import("@rails/actiontext"))
    .catch((error) => {
      actionTextLoadPromise = null
      console.error("Failed to load rich text editor", error)
    })

  return actionTextLoadPromise
}

const maybeLoadActionText = () => {
  if (document.querySelector("trix-editor")) loadActionText()
}

document.addEventListener("DOMContentLoaded", maybeLoadActionText)
document.addEventListener("turbo:load", maybeLoadActionText)
maybeLoadActionText();

// Compat mínimo para data-bs-* ainda usado em telas públicas não migradas.
(function () {
  if (window.__bsCompatShim) return;
  window.__bsCompatShim = true;

  const targetsOf = (el) => {
    const sel = el.getAttribute("data-bs-target") || el.getAttribute("href");
    if (!sel || sel === "#") return [];
    try { return Array.from(document.querySelectorAll(sel)); } catch (_) { return []; }
  };

  document.addEventListener("click", (event) => {
    const toggler = event.target.closest("[data-bs-toggle]");
    const dismiss = event.target.closest("[data-bs-dismiss]");

    if (dismiss) {
      if (dismiss.getAttribute("data-bs-dismiss") === "alert") dismiss.closest(".alert")?.remove();
      return;
    }

    if (!toggler) return;

    const kind = toggler.getAttribute("data-bs-toggle");

    if (kind === "collapse") {
      event.preventDefault();
      targetsOf(toggler).forEach((t) => t.classList.toggle("show"));
      toggler.setAttribute("aria-expanded", targetsOf(toggler).some((t) => t.classList.contains("show")));
    }
  });
})();
