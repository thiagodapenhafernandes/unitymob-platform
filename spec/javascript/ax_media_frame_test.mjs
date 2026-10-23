import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function frame(matches) {
  const listeners = new Set()
  const media = { matches, addEventListener: (_, fn) => listeners.add(fn), removeEventListener: (_, fn) => listeners.delete(fn) }
  const context = vm.createContext({ Controller: class {}, window: { matchMedia: () => media } })
  vm.runInContext(readFileSync("app/javascript/controllers/ax_media_frame_controller.js", "utf8")
    .replace(/^import .*\n/gm, "").replace("export default class", "this.Frame = class"), context)
  const controller = new context.Frame()
  const attributes = new Map()
  const requests = []
  controller.mediaValue = "(max-width: 767.98px)"
  controller.srcValue = "/admin/leads/pwa_section?origin=site&mobile_tab=all"
  controller.element = { hasAttribute: key => attributes.has(key), setAttribute: (key, value) => { attributes.set(key, value); requests.push(value) } }
  return { controller, media, requests, listeners }
}

test("desktop não inicia a seção mobile; redimensionamento carrega uma vez com os filtros", () => {
  const { controller, media, requests, listeners } = frame(false)
  controller.connect()
  assert.equal(requests.length, 0)
  media.matches = true
  for (const listener of listeners) listener()
  assert.deepEqual(requests, [controller.srcValue])
  media.matches = false
  for (const listener of listeners) listener()
  media.matches = true
  for (const listener of listeners) listener()
  assert.equal(requests.length, 1)
  controller.disconnect()
  assert.equal(listeners.size, 0)
})

test("mobile carrega ao conectar e reconectar não duplica a requisição", () => {
  const { controller, requests } = frame(true)
  controller.connect()
  assert.deepEqual(requests, [controller.srcValue])
  controller.disconnect()
  controller.connect()
  assert.equal(requests.length, 1)
})
