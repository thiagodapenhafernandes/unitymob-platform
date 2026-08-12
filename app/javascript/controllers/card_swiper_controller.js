import { Controller } from "@hotwired/stimulus"

let swiperBundlePromise = null

export default class extends Controller {
  static values = {
    priority: { type: Boolean, default: false }
  }

  connect() {
    if (this.priorityValue) {
      this.initializeSwiper()
      return
    }

    this.deferUntilNearViewport()
  }

  deferUntilNearViewport() {
    if (!("IntersectionObserver" in window)) {
      this.initializeSwiper()
      return
    }

    this.observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return

      this.observer?.disconnect()
      this.observer = null
      this.initializeSwiper()
    }, { rootMargin: "700px 0px" })

    this.observer.observe(this.element)
  }

  async initializeSwiper() {
    if (this.swiper || this.initializing) return

    this.initializing = true

    try {
      const Swiper = await this.loadSwiper()
      if (!this.element.isConnected || this.swiper) return

      this.swiper = new Swiper(this.element, {
        slidesPerView: 1,
        spaceBetween: 0,
        loop: false,
        effect: 'slide',
        speed: 300,
        watchOverflow: true,
        preventClicks: true,
        preventClicksPropagation: true,
        // Allow events to bubble
        touchEventsTarget: 'wrapper',
        nested: true,
        passiveListeners: true,
        observer: true,
        observeParents: true,
        resizeObserver: true,

        // Navigation arrows
        navigation: {
          nextEl: this.element.querySelector('.swiper-button-next'),
          prevEl: this.element.querySelector('.swiper-button-prev'),
        },

        // Pagination dots
        pagination: {
          el: this.element.querySelector('.swiper-pagination'),
          clickable: false,
          dynamicBullets: false,
        },

        // Stop clicks from bubbling to card link
        on: {
          init: (swiper) => {
            this.loadSlide(swiper.activeIndex)
          },
          slideChange: (swiper) => {
            this.loadSlide(swiper.activeIndex)
            this.loadSlide(swiper.activeIndex + 1)
          },
          click: (swiper, event) => {
            const target = event.target;
            // Only stop propagation on navigation elements
            if (target.closest('.swiper-button-next') ||
              target.closest('.swiper-button-prev') ||
              target.closest('.swiper-pagination')) {
              event.stopPropagation();
            }
          }
        }
      });
    } catch (error) {
      console.error('Error initializing card swiper:', error);
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

  keepInside(event) {
    event.stopPropagation()
  }

  loadSlide(index) {
    if (index < 0) return

    const slide = this.element.querySelectorAll(".swiper-slide")[index]
    if (!slide) return

    slide.querySelectorAll("img[data-src]").forEach((image) => {
      image.src = image.dataset.src
      image.removeAttribute("data-src")
    })
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }

    if (this.swiper) {
      this.swiper.destroy(true, true);
      this.swiper = null;
    }
  }
}
