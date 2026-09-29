import { Controller } from "@hotwired/stimulus"

// Cor "ambiente" do hero: em vez de sempre usar a cor fixa da marca na camada
// de contraste sobre a foto, extrai uma cor média da própria imagem (como o
// Canvas do Spotify) e usa como tom — o vão do blur e o degradê passam a
// conversar com as cores reais da foto, em vez de um véu genérico.
//
// Escurece a cor extraída só o necessário para o texto branco continuar
// legível (teto de luminância); fotos já escuras mantêm o tom quase intacto.
// Se o navegador não permitir ler os pixels (imagem sem CORS, Safari antigo
// etc.), simplesmente não define a variável e o CSS cai no valor padrão
// (cor da marca), sem quebrar nada.
export default class extends Controller {
  static targets = ["source"]

  static values = {
    property: { type: String, default: "--public-development-hero-tint" },
    maxLuminance: { type: Number, default: 0.32 }
  }

  connect() {
    if (!this.hasSourceTarget) return

    const image = this.sourceTarget
    if (image.complete && image.naturalWidth > 0) {
      this.extractTint(image)
    } else {
      image.addEventListener("load", () => this.extractTint(image), { once: true })
    }
  }

  extractTint(image) {
    try {
      const size = 16
      const canvas = document.createElement("canvas")
      canvas.width = size
      canvas.height = size

      const context = canvas.getContext("2d", { willReadFrequently: true })
      context.drawImage(image, 0, 0, size, size)
      const { data } = context.getImageData(0, 0, size, size)

      let r = 0, g = 0, b = 0, count = 0
      for (let i = 0; i < data.length; i += 4) {
        if (data[i + 3] < 200) continue
        r += data[i]
        g += data[i + 1]
        b += data[i + 2]
        count += 1
      }
      if (count === 0) return

      r /= count
      g /= count
      b /= count

      const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      if (luminance > this.maxLuminanceValue) {
        const scale = this.maxLuminanceValue / luminance
        r *= scale
        g *= scale
        b *= scale
      }

      this.element.style.setProperty(this.propertyValue, `rgb(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)})`)
    } catch {
      // Canvas "tainted" por CORS ou navegador sem suporte: mantém a cor da marca (fallback no CSS).
    }
  }
}
