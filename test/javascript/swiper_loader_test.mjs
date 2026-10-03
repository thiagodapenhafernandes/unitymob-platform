import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const frames = []
let link
const listeners = {}
const context = vm.createContext({
  window: { requestAnimationFrame(callback) { frames.push(callback) } },
  document: {
    querySelector() { return link },
    createElement() { return { dataset: {}, addEventListener(name, callback) { listeners[name] = callback } } },
    head: { appendChild(element) { link = element } }
  }
})
const source = readFileSync("app/javascript/controllers/swiper_loader.js", "utf8")
  .replace("export function", "function")
  .replace('import("swiper/bundle")', 'Promise.resolve({ default: "Swiper" })')
vm.runInContext(source, context)
const loading = context.loadSwiper()
assert.equal(context.loadSwiper(), loading)
assert.equal(link, undefined)
frames.shift()()
assert.equal(link, undefined)
frames.shift()()
await Promise.resolve()
assert.ok(link)
let ready = false
loading.then(() => { ready = true })
await Promise.resolve()
assert.equal(ready, false, "Não inicializar antes do CSS")
listeners.load()
assert.equal(await loading, "Swiper")
console.log("Swiper: primeira renderização, CSS e import compartilhado OK")
