import { Controller } from "@hotwired/stimulus"

// Seletor de cartão de apresentação (painel de contexto do inbox).
// Escolher um cartão NÃO envia nada: preenche o composer com o texto já
// resolvido ({nome}/{empresa}/{creci} substituídos no servidor) via evento
// global que o wa-composer escuta. O corretor revisa/edita e envia no botão
// normal — o card_id segue num hidden para carimbo/auditoria/gate.
//
//   <select data-controller="presentation-picker"
//           data-presentation-picker-presented-at-value="02/07 12:41"  (opcional)
//           data-action="change->presentation-picker#pick">
//     <option value="" ...>
//     <option value="123" data-body="..." data-card-id="123">...</option>
export default class extends Controller {
  static values = { presentedAt: String }

  pick(event) {
    const select = event.currentTarget
    const option = select.selectedOptions[0]
    if (!option || !option.value) return

    // Sem window.confirm aqui: o diálogo nativo tira a página do fullscreen.
    // Preencher é reversível — o envio continua atrás do botão Enviar.
    window.dispatchEvent(new CustomEvent("wa-presentation:fill", {
      detail: {
        cardId: option.dataset.cardId || option.value,
        body: option.dataset.body || ""
      }
    }))

    // Volta ao placeholder: o estado "escolhido" agora vive no composer.
    select.value = ""
  }
}
