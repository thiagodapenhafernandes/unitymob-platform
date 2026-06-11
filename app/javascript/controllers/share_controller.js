import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  copy(event) {
    event.preventDefault()
    const url = window.location.href

    navigator.clipboard.writeText(url).then(() => {
      // Feedback visual simples
      const originalHtml = this.linkTarget.innerHTML
      this.linkTarget.innerHTML = '<i class="fas fa-check text-green-500"></i>'

      setTimeout(() => {
        this.linkTarget.innerHTML = originalHtml
      }, 2000)
    }).catch(err => {
      console.error('Erro ao copiar URL: ', err)
    })
  }

  facebook(event) {
    event.preventDefault()
    const url = encodeURIComponent(window.location.href)
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${url}`, 'facebook-share-dialog', 'width=626,height=436')
  }

  twitter(event) {
    event.preventDefault()
    const url = encodeURIComponent(window.location.href)
    const text = encodeURIComponent(document.title)
    window.open(`https://twitter.com/intent/tweet?url=${url}&text=${text}`, 'twitter-share-dialog', 'width=626,height=436')
  }
}
