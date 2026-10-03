# Pin npm packages by running ./bin/importmap

# Preload do entrypoint só nos layouts que o usam (admin/field/wizard) — evita
# o waterfall HTML -> application.js -> controllers no boot de cada full load.
pin "application", preload: "application"
pin "public", preload: "public"
pin "ax_toast", preload: false
pin "submit_guard", preload: false
pin "pwa_scope_guard", preload: false
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js", preload: false
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
pin "lib/conditional_fields", to: "lib/conditional_fields.js", preload: false
pin "lib/currency_filter", to: "lib/currency_filter.js", preload: false
pin "lib/slide", to: "lib/slide.js", preload: false
pin_all_from "app/javascript/channels", under: "channels", preload: false
pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.mjs", preload: false
pin "tom-select", preload: false # @2.2.2 (vendor/javascript, self-host)
pin "trix", preload: false
pin "@rails/actiontext", to: "actiontext.esm.js", preload: false
pin "sortablejs", preload: false # @1.15.2 (vendor/javascript, self-host)
pin "@atlaskit/pragmatic-drag-and-drop/combine", to: "@atlaskit--pragmatic-drag-and-drop--combine.js", preload: false # @2.0.1 (self-host)
pin "@atlaskit/pragmatic-drag-and-drop/element/adapter", to: "@atlaskit--pragmatic-drag-and-drop--element--adapter.js", preload: false # @2.0.1 (self-host)
pin "@fancyapps/ui", to: "@fancyapps--ui.js", preload: false # @5.0.36 (vendor/javascript, self-host)
pin "@fingerprintjs/fingerprintjs", to: "@fingerprintjs--fingerprintjs.js", preload: false # @4.6.2 (vendor/javascript, self-host)
pin "intl-tel-input", to: "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/+esm", preload: false

pin "lib/navigation_loader", to: "lib/navigation_loader.js", preload: "application"
pin "lib/lead_attribution", to: "lib/lead_attribution.js"

# Os módulos da busca começam a baixar junto com o HTML público.
pin "controllers/application", to: "controllers/application.js", preload: "public"
pin "controllers/hero_search_controller", to: "controllers/hero_search_controller.js", preload: "public"
pin "controllers/hero_slider_controller", to: "controllers/hero_slider_controller.js", preload: "public"
pin "controllers/search_tabs_controller", to: "controllers/search_tabs_controller.js", preload: "public"
pin "controllers/category_filter_controller", to: "controllers/category_filter_controller.js", preload: "public"
pin "controllers/location_filter_controller", to: "controllers/location_filter_controller.js", preload: "public"
pin "controllers/filter_drawer_controller", to: "controllers/filter_drawer_controller.js", preload: "public"
