# Pin npm packages by running ./bin/importmap

pin "application", preload: false
pin "public"
pin "ax_toast", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
pin_all_from "app/javascript/channels", under: "channels", preload: false
pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.mjs", preload: false
pin "tom-select", to: "https://ga.jspm.io/npm:tom-select@2.2.2/dist/js/tom-select.complete.js", preload: false
pin "trix", preload: false
pin "@rails/actiontext", to: "actiontext.esm.js", preload: false
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.2/modular/sortable.esm.js", preload: false
pin "@atlaskit/pragmatic-drag-and-drop/combine", to: "https://esm.sh/@atlaskit/pragmatic-drag-and-drop@2.0.1/es2022/combine.bundle.mjs", preload: false
pin "@atlaskit/pragmatic-drag-and-drop/element/adapter", to: "https://esm.sh/@atlaskit/pragmatic-drag-and-drop@2.0.1/es2022/element/adapter.bundle.mjs", preload: false
