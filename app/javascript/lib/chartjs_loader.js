// Biblioteca opcional compartilhada pelos painéis; não faz parte do contrato de reload do Turbo.
export function loadChartJs(url) {
  if (window.Chart) return Promise.resolve()
  if (window.__axChartJsLoader) return window.__axChartJsLoader

  window.__axChartJsLoader = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.id = "ax-chartjs"
    script.src = url
    script.async = true
    script.addEventListener("load", resolve, { once: true })
    script.addEventListener("error", (error) => {
      script.remove()
      window.__axChartJsLoader = null
      reject(error)
    }, { once: true })
    document.head.appendChild(script)
  })
  return window.__axChartJsLoader
}
