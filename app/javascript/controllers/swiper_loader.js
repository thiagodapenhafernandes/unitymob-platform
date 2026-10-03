let swiperBundlePromise = null

export function loadSwiper() {
  if (!swiperBundlePromise) {
    swiperBundlePromise = new Promise((resolve) => {
      window.requestAnimationFrame(() => window.requestAnimationFrame(resolve))
    }).then(() => Promise.all([loadStylesheet(), import("swiper/bundle")]))
      .then(([, module]) => module.default)
  }

  return swiperBundlePromise
}

function loadStylesheet() {
  const existing = document.querySelector("link[data-swiper-css]")
  if (existing?.sheet) return Promise.resolve()

  return new Promise((resolve, reject) => {
    const link = existing || document.createElement("link")
    link.addEventListener("load", resolve, { once: true })
    link.addEventListener("error", () => reject(new Error("Não foi possível carregar o CSS do Swiper")), { once: true })
    if (existing) return

    link.rel = "stylesheet"
    link.href = "https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.css"
    link.dataset.swiperCss = "true"
    document.head.appendChild(link)
  })
}
