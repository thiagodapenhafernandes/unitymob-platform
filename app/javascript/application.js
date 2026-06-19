// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
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
maybeLoadActionText()

// ============================================================
//  Compat de data-* legados — handlers leves para os data-bs-*
//  ainda usados em telas PÚBLICAS não migradas (collapse, modal,
//  dropdown, offcanvas, dismiss). O admin não depende mais disto.
// ============================================================
(function () {
  if (window.__bsCompatShim) return;
  window.__bsCompatShim = true;

  const targetsOf = (el) => {
    const sel = el.getAttribute("data-bs-target") || el.getAttribute("href");
    if (!sel || sel === "#") return [];
    try { return Array.from(document.querySelectorAll(sel)); } catch (_) { return []; }
  };
  const closeBackdrops = () => document.querySelectorAll(".modal-backdrop, .offcanvas-backdrop").forEach((b) => b.remove());

  const openModal = (modal) => {
    if (!modal) return;
    closeBackdrops();
    modal.classList.add("show");
    modal.style.display = "block";
    const bd = document.createElement("div");
    bd.className = "modal-backdrop";
    if (modal.classList.contains("ax-attribute-modal")) bd.classList.add("ax-attribute-modal-backdrop");
    bd.addEventListener("click", () => closeModal(modal));
    document.body.appendChild(bd);
    document.body.classList.add("modal-open");
    document.documentElement.style.overflow = "hidden";
    modal.dispatchEvent(new Event("shown.bs.modal", { bubbles: true }));
  };
  const closeModal = (modal) => {
    if (!modal) return;
    modal.classList.remove("show");
    modal.style.display = "none";
    closeBackdrops();
    document.body.classList.remove("modal-open");
    document.documentElement.style.overflow = "";
    modal.dispatchEvent(new Event("hidden.bs.modal", { bubbles: true }));
  };

  document.addEventListener("click", (event) => {
    const toggler = event.target.closest("[data-bs-toggle]");
    const dismiss = event.target.closest("[data-bs-dismiss]");

    if (dismiss) {
      const kind = dismiss.getAttribute("data-bs-dismiss");
      if (kind === "modal") closeModal(dismiss.closest(".modal"));
      else if (kind === "offcanvas") { const oc = dismiss.closest(".offcanvas"); if (oc) oc.classList.remove("show"); closeBackdrops(); }
      else if (kind === "alert") { const a = dismiss.closest(".alert"); if (a) a.remove(); }
      return;
    }

    if (!toggler) {
      // clique fora fecha dropdowns abertos
      document.querySelectorAll(".dropdown-menu.show").forEach((m) => m.classList.remove("show"));
      return;
    }

    const kind = toggler.getAttribute("data-bs-toggle");

    if (kind === "collapse") {
      event.preventDefault();
      targetsOf(toggler).forEach((t) => t.classList.toggle("show"));
      toggler.setAttribute("aria-expanded", targetsOf(toggler).some((t) => t.classList.contains("show")));
    } else if (kind === "dropdown") {
      event.preventDefault(); event.stopPropagation();
      const menu = toggler.parentElement.querySelector(".dropdown-menu");
      const wasOpen = menu && menu.classList.contains("show");
      document.querySelectorAll(".dropdown-menu.show").forEach((m) => m.classList.remove("show"));
      if (menu && !wasOpen) menu.classList.add("show");
    } else if (kind === "modal") {
      event.preventDefault();
      openModal(targetsOf(toggler)[0]);
    } else if (kind === "tab" || kind === "pill") {
      event.preventDefault();
      const pane = targetsOf(toggler)[0];
      const navContainer = toggler.closest(".nav, .nav-tabs, .nav-pills, [role='tablist']");
      if (navContainer) navContainer.querySelectorAll("[data-bs-toggle]").forEach((t) => t.classList.remove("active"));
      toggler.classList.add("active");
      if (pane && pane.parentElement) {
        pane.parentElement.querySelectorAll(".tab-pane").forEach((p) => p.classList.remove("show", "active"));
        pane.classList.add("show", "active");
      }
    } else if (kind === "offcanvas") {
      event.preventDefault();
      const oc = targetsOf(toggler)[0];
      if (oc) {
        oc.classList.add("show");
        const bd = document.createElement("div");
        bd.className = "offcanvas-backdrop modal-backdrop";
        bd.addEventListener("click", () => { oc.classList.remove("show"); closeBackdrops(); });
        document.body.appendChild(bd);
      }
    }
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document.querySelectorAll(".modal.show").forEach(closeModal);
      document.querySelectorAll(".offcanvas.show").forEach((o) => o.classList.remove("show"));
      document.querySelectorAll(".dropdown-menu.show").forEach((m) => m.classList.remove("show"));
      closeBackdrops();
    }
  });

  // API construtor global (window.bootstrap) removida — o admin migrou para os
  // controllers ax-* (ax-modal/ax-tabs/ax-disclosure/ax-dropdown/ax-tooltip).
})();
