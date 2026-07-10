import "@hotwired/turbo-rails"
import { application } from "controllers/application"
import "ax_toast"

import AdvancedFiltersController from "controllers/advanced_filters_controller"
import AutocompleteController from "controllers/autocomplete_controller"
import BrokerShareController from "controllers/broker_share_controller"
import CardSwiperController from "controllers/card_swiper_controller"
import CategoryFilterController from "controllers/category_filter_controller"
import ClickableCardController from "controllers/clickable_card_controller"
import CodeSearchController from "controllers/code_search_controller"
import FancyboxGalleryController from "controllers/fancybox_gallery_controller"
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
import PublicFavoritesController from "controllers/public_favorites_controller"
import PublicGalleryMobileController from "controllers/public_gallery_mobile_controller"
import SearchFormController from "controllers/search_form_controller"
import SearchTabsController from "controllers/search_tabs_controller"
import ShareController from "controllers/share_controller"
import SidebarController from "controllers/sidebar_controller"
import TransactionToggleController from "controllers/transaction_toggle_controller"

application.register("advanced-filters", AdvancedFiltersController)
application.register("autocomplete", AutocompleteController)
application.register("broker-share", BrokerShareController)
application.register("card-swiper", CardSwiperController)
application.register("category-filter", CategoryFilterController)
application.register("clickable-card", ClickableCardController)
application.register("code-search", CodeSearchController)
application.register("fancybox-gallery", FancyboxGalleryController)
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
application.register("public-favorites", PublicFavoritesController)
application.register("public-gallery-mobile", PublicGalleryMobileController)
application.register("search-form", SearchFormController)
application.register("search-tabs", SearchTabsController)
application.register("share", ShareController)
application.register("sidebar", SidebarController)
application.register("transaction-toggle", TransactionToggleController)
