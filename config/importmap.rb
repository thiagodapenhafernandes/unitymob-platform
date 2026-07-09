# Pin npm packages by running ./bin/importmap

# Preload do entrypoint só nos layouts que o usam (admin/field/wizard) — evita
# o waterfall HTML -> application.js -> controllers no boot de cada full load.
pin "application", preload: "application"
pin "public"
pin "ax_toast", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
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
