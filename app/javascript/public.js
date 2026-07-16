import "@hotwired/turbo-rails"
import { application } from "controllers/application"
import "ax_toast"

// Controllers presentes na home / above-the-fold / modais sempre no DOM:
// registro eager para evitar qualquer regressao no fluxo publico principal.
import AutocompleteController from "controllers/autocomplete_controller"
import BrokerShareController from "controllers/broker_share_controller"
import CardSwiperController from "controllers/card_swiper_controller"
import CategoryFilterController from "controllers/category_filter_controller"
import ClickableCardController from "controllers/clickable_card_controller"
import CodeSearchController from "controllers/code_search_controller"
import FiltersController from "controllers/filters_controller"
import HeroSliderController from "controllers/hero_slider_controller"
import LeadCaptureController from "controllers/lead_capture_controller"
import LgpdConsentController from "controllers/lgpd_consent_controller"
import LocationFilterController from "controllers/location_filter_controller"
import MarketingTrackerController from "controllers/marketing_tracker_controller"
import NavbarController from "controllers/navbar_controller"
import PhotoGalleryController from "controllers/photo_gallery_controller"
import PhoneInputController from "controllers/phone_input_controller"
import PropertyCarouselController from "controllers/property_carousel_controller"
import PublicPropertyMapController from "controllers/public_property_map_controller"
import SearchFormController from "controllers/search_form_controller"
import SearchTabsController from "controllers/search_tabs_controller"
import ShareController from "controllers/share_controller"
import TransactionToggleController from "controllers/transaction_toggle_controller"

application.register("autocomplete", AutocompleteController)
application.register("broker-share", BrokerShareController)
application.register("card-swiper", CardSwiperController)
application.register("category-filter", CategoryFilterController)
application.register("clickable-card", ClickableCardController)
application.register("code-search", CodeSearchController)
application.register("filters", FiltersController)
application.register("hero-slider", HeroSliderController)
application.register("lead-capture", LeadCaptureController)
application.register("lgpd-consent", LgpdConsentController)
application.register("location-filter", LocationFilterController)
application.register("marketing-tracker", MarketingTrackerController)
application.register("navbar", NavbarController)
application.register("photo-gallery", PhotoGalleryController)
application.register("phone-input", PhoneInputController)
application.register("property-carousel", PropertyCarouselController)
application.register("public-property-map", PublicPropertyMapController)
application.register("search-form", SearchFormController)
application.register("search-tabs", SearchTabsController)
application.register("share", ShareController)
application.register("transaction-toggle", TransactionToggleController)

// Perf: controllers exclusivos de paginas internas (show / index / favoritos)
// -> nunca aparecem na home. Import sob demanda so quando o data-controller
// esta no HTML inicial da pagina, reduzindo os requests JS da home.
// Padrao gated (querySelector) em vez de lazyLoadControllersFrom para NAO
// acordar controllers dormentes de proposito (ex.: public-interest-tracker).
const pageScopedControllers = [
  ["advanced-filters", () => import("controllers/advanced_filters_controller")],
  ["fancybox-gallery", () => import("controllers/fancybox_gallery_controller")],
  ["public-favorites", () => import("controllers/public_favorites_controller")],
  ["public-gallery-mobile", () => import("controllers/public_gallery_mobile_controller")],
  ["sidebar", () => import("controllers/sidebar_controller")]
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
