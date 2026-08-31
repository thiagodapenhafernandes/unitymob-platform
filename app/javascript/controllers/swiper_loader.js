let swiperBundlePromise = null

export function loadSwiper() {
  if (!swiperBundlePromise) {
    loadStylesheet()
    swiperBundlePromise = import("swiper/bundle").then((module) => module.default)
  }

  return swiperBundlePromise
}

function loadStylesheet() {
  if (document.querySelector("link[data-swiper-css]")) return

  const link = document.createElement("link")
  link.rel = "stylesheet"
  link.href = "https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.css"
  link.dataset.swiperCss = "true"
  document.head.appendChild(link)
}
