import { Controller } from "@hotwired/stimulus"
import Swiper from "swiper/bundle"

export default class extends Controller {
  connect() {
    this.initSwiper()
    this.initFancybox()
  }

  initSwiper() {
    if (this.swiper) return

    // Elementos de navegação
    const nextEl = this.element.querySelector('.swiper-button-next')
    const prevEl = this.element.querySelector('.swiper-button-prev')
    const paginationEl = this.element.querySelector('.swiper-pagination')

    this.swiper = new Swiper(this.element, {
      slidesPerView: 1,
      spaceBetween: 0,

      // Navigation
      navigation: {
        nextEl: nextEl,
        prevEl: prevEl,
      },

      // Pagination
      pagination: {
        el: paginationEl,
        clickable: true,
        dynamicBullets: true,
      },

      // Loop se houver mais de uma imagem
      loop: this.element.querySelectorAll('.swiper-slide').length > 1,

      // Keyboard
      keyboard: {
        enabled: true,
      },

      // Lazy loading
      lazy: true,

      // Observer
      observer: true,
      observeParents: true,
    })
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
