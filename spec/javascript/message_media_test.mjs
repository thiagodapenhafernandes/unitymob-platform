import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function setup(auto = true) {
  const context = vm.createContext({ Controller: class {}, document: { createElement: (tag) => ({ tagName: tag.toUpperCase(), dataset: {}, addEventListener(name, fn) { this[name] = fn } }) } })
  vm.runInContext(readFileSync("app/javascript/controllers/message_media_controller.js", "utf8").replace(/^import .*\n/, "").replace("export default class", "this.C = class"), context)
  const controller = new context.C()
  controller.autoValue = auto
  const classes = new Set()
  controller.element = { classList: { add: (name) => classes.add(name) } }
  return { controller, classes }
}

test("story sem tipo tenta vídeo após imagem falhar e mostra erro se o vídeo também falhar", () => {
  const { controller, classes } = setup()
  let video
  controller.failed({ currentTarget: { tagName: "IMG", src: "https://example.test/story", className: "media", replaceWith: (node) => { video = node } } })
  assert.equal(video.tagName, "VIDEO")
  assert.equal(video.src, "https://example.test/story")
  assert.equal(video.controls, true)
  assert.equal(video.playsInline, true)
  assert.equal(video.preload, "metadata")
  assert.equal(video.autoplay, undefined)
  video.error()
  assert.equal(video.hidden, true)
  assert.equal(classes.has("is-image-missing"), true)
})

test("tipos conhecidos não tentam outro player e falhas anteriores ao connect são tratadas", () => {
  const { controller, classes } = setup(false)
  const media = { tagName: "IMG", complete: true, naturalWidth: 0 }
  controller.hasMediaTarget = true
  controller.mediaTarget = media
  controller.connect()
  assert.equal(media.hidden, true)
  assert.equal(classes.has("is-image-missing"), true)
})
