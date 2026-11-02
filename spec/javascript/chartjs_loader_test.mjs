import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { loadChartJs } from "../../app/javascript/lib/chartjs_loader.js"

const originalWindow = globalThis.window
const originalDocument = globalThis.document
afterEach(() => {
  globalThis.window = originalWindow
  globalThis.document = originalDocument
})

function setup() {
  const scripts = []
  globalThis.window = {}
  globalThis.document = {
    createElement: () => ({
      dataset: {}, listeners: {},
      addEventListener(type, callback) { this.listeners[type] = callback },
      remove() { scripts.splice(scripts.indexOf(this), 1) }
    }),
    head: { appendChild: script => scripts.push(script) }
  }
  return scripts
}

test("compartilha uma carga entre painéis sem invalidar o head do Turbo", async () => {
  const scripts = setup()
  const first = loadChartJs("/assets/chart.js")
  const second = loadChartJs("/assets/chart.js")
  assert.equal(first, second)
  assert.equal(scripts.length, 1)
  assert.notEqual(scripts[0].dataset.turboTrack, "reload")
  scripts[0].listeners.load()
  await Promise.all([first, second])
})

test("retorno ao painel reutiliza a biblioteca já carregada", async () => {
  const scripts = setup()
  window.Chart = function Chart() {}
  await loadChartJs("/assets/chart.js")
  assert.equal(scripts.length, 0)
})

test("falha remove o script e permite tentar novamente", async () => {
  const scripts = setup()
  const failed = loadChartJs("/assets/chart.js")
  scripts[0].listeners.error(new Error("rede indisponível"))
  await assert.rejects(failed, /rede indisponível/)
  assert.equal(scripts.length, 0)
  const retry = loadChartJs("/assets/chart.js")
  scripts[0].listeners.load()
  await retry
  assert.equal(scripts.length, 1)
})
