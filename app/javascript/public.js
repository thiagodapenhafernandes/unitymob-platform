import "@hotwired/turbo-rails"
import { application } from "controllers/application"
import "ax_toast"
import "pwa_scope_guard"

// Controllers presentes na home / above-the-fold / modais sempre no DOM:
// registro eager para evitar qualquer regressao no fluxo publico principal.
import AutocompleteController from "controllers/autocomplete_controller"
import CategoryFilterController from "controllers/category_filter_controller"
import CardSwiperController from "controllers/card_swiper_controller"
import ClickableCardController from "controllers/clickable_card_controller"
import CodeSearchController from "controllers/code_search_controller"
import ComboboxController from "controllers/combobox_controller"
import FiltersController from "controllers/filters_controller"
import FilterDrawerController from "controllers/filter_drawer_controller"
import HeroSearchController from "controllers/hero_search_controller"
import HeroSliderController from "controllers/hero_slider_controller"
import InputMaskController from "controllers/input_mask_controller"
import LeadCaptureController from "controllers/lead_capture_controller"
import LgpdConsentController from "controllers/lgpd_consent_controller"
import LocationFilterController from "controllers/location_filter_controller"
import MarketingTrackerController from "controllers/marketing_tracker_controller"
import NavbarController from "controllers/navbar_controller"
import PhoneInputController from "controllers/phone_input_controller"
import PropertyCarouselController from "controllers/property_carousel_controller"
import PublicInterestTrackerController from "controllers/public_interest_tracker_controller"
import PublicFormModalController from "controllers/public_form_modal_controller"
import PublicModalTriggerController from "controllers/public_modal_trigger_controller"
import PublicSearchUrlController from "controllers/public_search_url_controller"
import SearchFormController from "controllers/search_form_controller"
import SearchTabsController from "controllers/search_tabs_controller"
import TransactionToggleController from "controllers/transaction_toggle_controller"

application.register("autocomplete", AutocompleteController)
application.register("category-filter", CategoryFilterController)
application.register("card-swiper", CardSwiperController)
application.register("clickable-card", ClickableCardController)
application.register("code-search", CodeSearchController)
application.register("combobox", ComboboxController)
application.register("filters", FiltersController)
application.register("filter-drawer", FilterDrawerController)
application.register("hero-search", HeroSearchController)
application.register("hero-slider", HeroSliderController)
application.register("input-mask", InputMaskController)
application.register("lead-capture", LeadCaptureController)
application.register("lgpd-consent", LgpdConsentController)
application.register("location-filter", LocationFilterController)
application.register("marketing-tracker", MarketingTrackerController)
application.register("navbar", NavbarController)
application.register("phone-input", PhoneInputController)
application.register("property-carousel", PropertyCarouselController)
application.register("public-interest-tracker", PublicInterestTrackerController)
application.register("public-form-modal", PublicFormModalController)
application.register("public-modal-trigger", PublicModalTriggerController)
application.register("public-search-url", PublicSearchUrlController)
application.register("search-form", SearchFormController)
application.register("search-tabs", SearchTabsController)
application.register("transaction-toggle", TransactionToggleController)

// Perf: controllers exclusivos de paginas internas (show / index / favoritos)
// -> nunca aparecem na home. Import sob demanda so quando o data-controller
// esta no HTML inicial da pagina, reduzindo os requests JS da home.
// Padrao gated (querySelector) em vez de lazyLoadControllersFrom para NAO
// acordar controllers dormentes de proposito (ex.: public-interest-tracker).
const pageScopedControllers = [
  ["broker-share", () => import("controllers/broker_share_controller")],
  ["fancybox-gallery", () => import("controllers/fancybox_gallery_controller")],
  ["home-video-showcase", () => import("controllers/home_video_showcase_controller")],
  ["photo-gallery", () => import("controllers/photo_gallery_controller")],
  ["property-share-interest", () => import("controllers/property_share_interest_controller")],
  ["public-property-map", () => import("controllers/public_property_map_controller")],
  ["public-file-field", () => import("controllers/public_file_field_controller")],
  ["share", () => import("controllers/share_controller")],
  ["advanced-filters", () => import("controllers/advanced_filters_controller")],
  ["collapsible-text", () => import("controllers/collapsible_text_controller")],
  ["currency-mask", () => import("controllers/currency_mask_controller")],
  ["financing-simulator", () => import("controllers/financing_simulator_controller")],
  ["financing-modal", () => import("controllers/financing_modal_controller")],
  ["financing-modal-trigger", () => import("controllers/financing_modal_trigger_controller")],
  ["image-fallback", () => import("controllers/image_fallback_controller")],
  ["navigation-overlay", () => import("controllers/navigation_overlay_controller")],
  ["public-favorites", () => import("controllers/public_favorites_controller")],
  ["public-gallery-mobile", () => import("controllers/public_gallery_mobile_controller")],
  ["public-listing-nav", () => import("controllers/public_listing_nav_controller")],
  ["public-progressive-reveal", () => import("controllers/public_progressive_reveal_controller")],
  ["sidebar", () => import("controllers/sidebar_controller")],
  ["salute-luxury-theme", () => import("controllers/salute_luxury_theme_controller")],
  ["public-card-gallery", () => import("controllers/public_card_gallery_controller")],
  ["public-card-strip", () => import("controllers/public_card_strip_controller")],
  ["public-property-favorite", () => import("controllers/public_property_favorite_controller")]
]

const loadedPageScoped = new Set()

function loadPageScopedControllers() {
  pageScopedControllers.forEach(([name, loader]) => {
    if (loadedPageScoped.has(name)) return
    if (!document.querySelector(`[data-controller~="${name}"]`)) return

    loadedPageScoped.add(name)
    loader()
      .then((module) => application.register(name, module.default))
      .catch((error) => {
        loadedPageScoped.delete(name)
        console.error(`[stimulus] falha ao carregar ${name}:`, error)
      })
  })
}

// turbo:load dispara no load inicial E apos cada navegacao Turbo Drive,
// garantindo o registro mesmo ao navegar da home para uma pagina interna.
document.addEventListener("turbo:load", loadPageScopedControllers)

document.addEventListener("turbo:frame-load", loadPageScopedControllers)
