import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const source = readFileSync("app/javascript/controllers/ax_event_race_controller.js", "utf8")
test("todos os participantes, ausência de entrega e canais independentes", () => {
  let chart
  const nodes = new Map()
  const channels = ["whatsapp", "push"].map(channel => ({ dataset: { channel }, setAttribute() {} }))
  const periods = ["300", "all"].map(window => ({ dataset: { window }, setAttribute() {} }))
  const element = {
    querySelector(selector) {
      if (!nodes.has(selector)) nodes.set(selector, { style: {}, textContent: "" })
      return nodes.get(selector)
    },
    querySelectorAll(selector) { return selector === "[data-channel]" ? channels : periods }
  }
  const drawRace = new Function("window", source.slice(source.indexOf("function drawRace")) + ";return drawRace")({
    Chart: class {
      constructor(canvas, config) { Object.assign(this, config); chart = this }
      update() {}
    }
  })
  const cycle = { start: "2026-09-13T11:00:00-03:00", duration: 2520,
    rows: Array.from({length: 12}, (_, id) => ({ id, name: "Corretor " + id, points: id < 2 ? [
      { channel: "whatsapp", state: "Recebeu", at: "2026-09-13T11:00:04-03:00" },
      { channel: "whatsapp", state: "Leu", at: "2026-09-13T11:01:00-03:00" }
    ] : [] })) }
  drawRace(element, cycle, "America/Sao_Paulo")
  assert.equal(chart.options.scales.y.max, 11.5)
  assert.equal(nodes.get("[data-race-chart]").style.height, "588px")
  assert.equal(nodes.get("[data-race-delivered]").textContent, 2)
  const received = chart.data.datasets.flatMap(d => d.data).filter(p => p.k === "Recebeu")
  assert.deepEqual(received.map(p => p.x), [0,0])
  assert.match(chart.options.plugins.tooltip.callbacks.label({raw:received[0]}), /11:00$/)
  assert.equal(received[0].s, 4)
  channels[1].onclick()
  assert.equal(nodes.get("[data-race-delivered]").textContent, 0)
  assert.equal(nodes.get("[data-race-read]").textContent, "—")
  assert.equal(chart.options.scales.y.max, 11.5)
  periods[1].onclick()
  assert.equal(chart.options.scales.x.max, 2520)
})
