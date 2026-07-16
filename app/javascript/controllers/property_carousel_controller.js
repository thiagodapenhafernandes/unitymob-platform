import { Controller } from "@hotwired/stimulus"
import Swiper from "swiper/bundle"

export default class extends Controller {
  connect() {
    this.initSwiper()
  }

  initSwiper() {
    if (this.swiper) return

    // Encontrar wrapper pai
    const wrapper = this.element.closest('.property-carousel-wrapper')

    if (!wrapper) {
      console.error('Property carousel wrapper not found')
      return
    }

    // Buscar elementos dentro do wrapper específico deste carousel
    const nextEl = wrapper.querySelector('.property-carousel-next')
    const prevEl = wrapper.querySelector('.property-carousel-prev')
    const paginationEl = wrapper.querySelector('.swiper-pagination')

    this.swiper = new Swiper(this.element, {
      // Mobile first (1 slide)
      slidesPerView: 1,
      spaceBetween: 20,

      // Navigation - passar os elementos diretamente
      navigation: {
        nextEl: nextEl,
        prevEl: prevEl,
        disabledClass: 'swiper-button-disabled',
      },

      // Pagination
      pagination: {
        el: paginationEl,
        clickable: false,
        dynamicBullets: true,
      },

      // Breakpoints explícitos
      breakpoints: {
        // Tablet (>= 640px)
        640: {
          slidesPerView: 2,
          spaceBetween: 20,
        },
        // Desktop (>= 1024px)
        1024: {
          slidesPerView: 3,
          spaceBetween: 30,
        },
        // Large Desktop (>= 1280px)
        1280: {
          slidesPerView: 3,
          spaceBetween: 30,
        }
      },

      // Loop apenas se houver slides suficientes
      loop: this.element.querySelectorAll('.swiper-slide').length > 3,

      // Observer para mudanças
      observer: true,
      observeParents: true,
      watchOverflow: true,

      // CRITICAL: Prevenir navegação ao arrastar
      threshold: 5, // Mínimo de 5px para considerar como drag
      touchRatio: 1,
      touchAngle: 45,

      // Prevenir cliques quando há movimento
      preventClicks: true,
      preventClicksPropagation: true,

      // Só considera como clique se não houver movimento
      touchMoveStopPropagation: true,

      on: {}
    })
  }

  disconnect() {
    if (this.swiper) {
      this.swiper.destroy()
      this.swiper = null
    }
  }
}
