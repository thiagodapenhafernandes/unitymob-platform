import { test } from "node:test"
import assert from "node:assert/strict"
import { createNavigationLoader } from "../../app/javascript/lib/navigation_loader.js"

function setup({ controllers = [], frames = [], images = [] } = {}) {
  const listeners = {}
  const classes = new Set()
  const overlay = {
    hidden: true,
    classList: { add: (...c) => c.forEach(x => classes.add("o:" + x)), remove: (...c) => c.forEach(x => classes.delete("o:" + x)) },
    querySelector: () => ({ textContent: "" })
  }
  const state = { controllers: [...controllers], frames: [...frames], images: [...images], connected: new Set() }
  const document = {
    documentElement: { classList: { add: c => classes.add(c), remove: c => classes.delete(c) }, hasAttribute: () => false },
    getElementById: () => overlay,
    addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn) },
    querySelector: () => null,
    querySelectorAll: selector => (selector === "[data-controller]" ? state.controllers : selector === "img" ? state.images : state.frames)
  }
  const timers = []
  const window = {
    location: { pathname: "/admin", search: "", href: "http://x/admin" },
    innerHeight: 800,
    requestAnimationFrame: fn => { setImmediate(fn) },
    setTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length },
    clearTimeout() {},
    addEventListener: (type, fn) => { (listeners["window:" + type] ||= []).push(fn) },
    Stimulus: {
      getControllerForElementAndIdentifier: (el, id) => (state.connected.has(el) ? {} : null),
      router: { modulesByIdentifier: new Map([["drawer", {}]]) }
    }
  }
  const loader = createNavigationLoader({ document, window })
  const fire = (type, event = {}) => (listeners[type] || []).forEach(fn => fn(event))
  const flush = async () => { for (let i = 0; i < 12; i += 1) await new Promise(resolve => setImmediate(resolve)) }
  return { loader, fire, flush, overlay, classes, state, timers }
}

const visit = url => ({ detail: { url } })

test("mostra em turbo:visit e só esconde depois de turbo:load + paint", async () => {
  const { fire, flush, overlay, classes } = setup()
  fire("turbo:visit", visit("http://x/admin/leads"))
  assert.equal(overlay.hidden, false)
  assert.ok(classes.has("ax-admin-is-loading"))
  await flush()
  assert.equal(overlay.hidden, false, "render do DOM sozinho não encerra")
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, true)
  assert.equal(classes.has("ax-admin-is-loading"), false)
})

test("não esconde enquanto um controller da página ainda não conectou", async () => {
  const el = { getAttribute: () => "drawer" }
  const { fire, flush, overlay, state } = setup({ controllers: [el] })
  fire("turbo:visit", visit("http://x/admin/leads"))
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, false)
  state.connected.add(el)
  await flush()
  assert.equal(overlay.hidden, true)
})

test("não esconde enquanto um turbo-frame visível está carregando; frame lazy fora da tela não segura", async () => {
  const attrs = new Set(["busy"])
  const frame = { dataset: {}, getAttribute: () => null, hasAttribute: a => attrs.has(a), getBoundingClientRect: () => ({ top: 10, bottom: 50 }) }
  const lazyOff = { dataset: {}, getAttribute: () => "lazy", hasAttribute: () => false, getBoundingClientRect: () => ({ top: 5000, bottom: 5100 }) }
  const { fire, flush, overlay, state } = setup({ frames: [frame, lazyOff] })
  fire("turbo:visit", visit("http://x/admin"))
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, false)
  attrs.delete("busy"); attrs.add("complete")
  await flush()
  assert.equal(overlay.hidden, true)
})

test("teto de espera: controller que nunca conecta não prende o overlay", async () => {
  const el = { getAttribute: () => "drawer" }
  const { fire, flush, overlay, timers } = setup({ controllers: [el] })
  fire("turbo:visit", visit("http://x/admin"))
  fire("turbo:load")
  await flush()
  const gate = timers.find(t => t.ms === 5000)
  assert.ok(gate, "timeout do gate armado")
  gate.fn()
  await flush()
  assert.equal(overlay.hidden, true)
})

test("navegação nova invalida o settle da anterior", async () => {
  const el = { getAttribute: () => "drawer" }
  const { fire, flush, overlay, state } = setup({ controllers: [el] })
  fire("turbo:visit", visit("http://x/admin/a"))
  fire("turbo:load")
  await flush()
  fire("turbo:visit", visit("http://x/admin/b"))
  state.connected.add(el)
  await flush()
  assert.equal(overlay.hidden, false, "o settle antigo não pode esconder a visita nova")
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, true)
})

test("ignora âncora na mesma página, cliques marcados e forms de frame", async () => {
  const { fire, overlay } = setup()
  fire("turbo:visit", visit("http://x/admin#secao"))
  assert.equal(overlay.hidden, true)
  fire("turbo:click", { target: { dataset: {}, closest: s => (s === "[data-admin-navigation-ignore]" ? {} : null) } })
  fire("turbo:visit", visit("http://x/admin/x"))
  assert.equal(overlay.hidden, true)
  fire("turbo:submit-start", { target: { dataset: { turboFrame: "modal" }, closest: () => null } })
  assert.equal(overlay.hidden, true)
  fire("turbo:submit-start", { target: { dataset: {}, closest: () => null } })
  assert.equal(overlay.hidden, false)
})

test("resposta não-HTML (download) libera o overlay sem trocar de página", async () => {
  const { fire, flush, overlay, timers } = setup()
  fire("turbo:visit", visit("http://x/admin/export"))
  fire("turbo:reload", { detail: { reason: "request_failed", context: { statusCode: -2 } } })
  const t = timers.find(x => x.ms === 1200)
  assert.ok(t)
  t.fn()
  assert.equal(overlay.hidden, true)
})

test("hold segura o fim da navegação até resolver", async () => {
  const { loader, fire, flush, overlay } = setup()
  fire("turbo:visit", visit("http://x/admin"))
  let release
  loader.hold(new Promise(r => { release = r }))
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, false)
  release()
  await flush()
  assert.equal(overlay.hidden, true)
})

test("segura o overlay por imagem visível ainda carregando; imagem fora da tela ou já completa não segura", async () => {
  const visible = { complete: false, getBoundingClientRect: () => ({ top: 100, bottom: 300 }) }
  const offscreen = { complete: false, getBoundingClientRect: () => ({ top: 4000, bottom: 4200 }) }
  const { fire, flush, overlay } = setup({ images: [visible, offscreen] })
  fire("turbo:visit", visit("http://x/admin/habitations"))
  fire("turbo:load")
  await flush()
  assert.equal(overlay.hidden, false)
  visible.complete = true
  await flush()
  assert.equal(overlay.hidden, true)
})
