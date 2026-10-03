import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync("app/javascript/controllers/filter_drawer_controller.js", "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace("export default class", "globalThis.Drawer = class")
const context = vm.createContext({
  document: { addEventListener() {} },
  window: { requestAnimationFrame() {} }
})
vm.runInContext(source, context)
const drawer = new context.Drawer()
let mounted = 0
const controls = { selectedCity: "Balneário Camboriú" }
drawer.hasContentTarget = true
drawer.contentTarget = { content: controls, replaceWith(content) {
  assert.equal(content, controls)
  mounted += 1
  drawer.hasContentTarget = false
} }
drawer.hasVisualTarget = true
drawer.visualTarget = { dataset: { backgroundUrl: "https://cdn.example.com/fundo.webp" }, style: {} }
drawer.drawerTarget = { classList: { add() {} }, setAttribute() {} }
drawer.triggerTargets = []
drawer.lockScroll = drawer.drawAllRanges = () => {}
assert.equal(drawer.visualTarget.style.backgroundImage, undefined)
drawer.open()
assert.equal(mounted, 1)
assert.equal(controls.selectedCity, "Balneário Camboriú")
assert.equal(drawer.visualTarget.style.backgroundImage, 'url("https://cdn.example.com/fundo.webp")')
assert.equal(drawer.visualTarget.dataset.backgroundUrl, undefined)
drawer.open()
assert.equal(mounted, 1)
assert.equal(controls.selectedCity, "Balneário Camboriú")
assert.equal(drawer.visualTarget.style.backgroundImage, 'url("https://cdn.example.com/fundo.webp")')
console.log("Imagem do filtro: carregamento na abertura e reabertura OK")
