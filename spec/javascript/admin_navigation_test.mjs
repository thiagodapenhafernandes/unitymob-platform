import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function setup(overlay) {
  const classes = new Set(["ax-admin-is-loading"])
  const timers = []
  const context = vm.createContext({
    Controller: class {},
    performance: { now: () => 5000, getEntriesByType: () => [] },
    document: {
      addEventListener() {}, removeEventListener() {},
      documentElement: {
        dataset: {},
        classList: { contains: value => classes.has(value), remove: value => classes.delete(value) }
      }
    },
    window: {
      addEventListener() {}, removeEventListener() {},
      requestAnimationFrame: callback => callback(),
      clearTimeout() {},
      setTimeout: (callback, delay) => { timers.push({ callback, delay }); return timers.length }
    }
  })
  vm.runInContext(
    readFileSync("app/javascript/controllers/admin_navigation_controller.js", "utf8")
      .replace(/^import .*\n/, "")
      .replace("export default class", "this.Navigation = class"),
    context
  )
  const controller = new context.Navigation()
  controller.element = { dataset: {} }
  controller.hasOverlayTarget = Boolean(overlay)
  Object.defineProperty(controller, "overlayTarget", {
    get() {
      if (!controller.hasOverlayTarget) throw new Error('Missing target element "overlay"')
      return overlay
    }
  })
  return { controller, classes, timers }
}

test("conecta sem overlay e libera o estado de carregamento sem lançar erro", () => {
  const { controller, classes, timers } = setup()
  assert.doesNotThrow(() => controller.connect())
  assert.equal(classes.has("ax-admin-is-loading"), false)
  assert.equal(timers.length, 0)
  assert.equal(controller.failsafeElapsed(), true)
  assert.doesNotThrow(() => controller.disconnect())
})

test("mantém o prazo do failsafe e libera frames se o overlay desaparecer", () => {
  const { controller, timers, classes } = setup({ dataset: { shownAt: "1000" } })
  controller.armFailsafe()
  assert.equal(timers[0].delay, 6000)
  assert.equal(controller.failsafeElapsed(), false)
  let resumed = false
  controller.pendingFrameResumes = [() => { resumed = true }]
  controller.hasOverlayTarget = false
  assert.doesNotThrow(() => timers[0].callback())
  assert.equal(resumed, true)
  assert.equal(classes.has("ax-admin-is-loading"), false)
})
