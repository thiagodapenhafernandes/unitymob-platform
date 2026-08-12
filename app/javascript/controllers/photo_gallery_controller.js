import { Controller } from "@hotwired/stimulus"

let swiperBundlePromise = null

export default class extends Controller {
  connect() {
    this.initSwiper()
    this.initFancybox()
  }

  async initSwiper() {
    if (this.swiper || this.initializing) return

    this.initializing = true

    try {
      const Swiper = await this.loadSwiper()
      if (!this.element.isConnected || this.swiper) return

      const nextEl = this.element.querySelector('.swiper-button-next')
      const prevEl = this.element.querySelector('.swiper-button-prev')
      const paginationEl = this.element.querySelector('.swiper-pagination')

      this.swiper = new Swiper(this.element, {
        slidesPerView: 1,
        spaceBetween: 0,

        navigation: {
          nextEl: nextEl,
          prevEl: prevEl,
        },

        pagination: {
          el: paginationEl,
          clickable: true,
          dynamicBullets: true,
        },

        loop: this.element.querySelectorAll('.swiper-slide').length > 1,

        keyboard: {
          enabled: true,
        },

        lazy: true,
        observer: true,
        observeParents: true,
      })
    } catch (error) {
      console.error('Error initializing photo gallery:', error)
    } finally {
      this.initializing = false
    }
  }

  loadSwiper() {
    if (!swiperBundlePromise) {
      this.loadStylesheet()
      swiperBundlePromise = import("swiper/bundle").then((module) => module.default)
    }

    return swiperBundlePromise
  }

  loadStylesheet() {
    if (document.querySelector("link[data-swiper-css]")) return

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = "https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.css"
    link.dataset.swiperCss = "true"
    document.head.appendChild(link)
  }

  initFancybox() {
    if (typeof Fancybox !== 'undefined') {
      Fancybox.bind(this.element, "[data-fancybox]", {
        // Opções do Fancybox se necessário
        Toolbar: {
          display: {
            left: ["infobar"],
            middle: [
              "zoomIn",
              "zoomOut",
              "toggle1to1",
              "rotateCCW",
              "rotateCW",
              "flipX",
              "flipY",
            ],
            right: ["slideshow", "thumbs", "close"],
          },
        },
      })
    }
  }

  disconnect() {
    if (this.swiper) {
      this.swiper.destroy()
      this.swiper = null
    }

    if (typeof Fancybox !== 'undefined') {
      Fancybox.destroy()
    }
  }
}
