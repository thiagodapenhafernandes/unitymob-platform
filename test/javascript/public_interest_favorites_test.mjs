import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
const storageSource = await readFile(new URL('../../app/javascript/controllers/public_favorites_storage.js', import.meta.url), 'utf8')
const storageUrl = `data:text/javascript;base64,${Buffer.from(storageSource).toString('base64')}`
const source = (await readFile(new URL('../../app/javascript/controllers/public_interest_tracker_controller.js', import.meta.url), 'utf8'))
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
  .replace('"controllers/public_favorites_storage"', JSON.stringify(storageUrl))
const { default: Tracker } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
let saved = null
let consent = true
const sent = []
globalThis.document = { body: { dataset: { publicTenantSlug: 'test' } }, querySelector: () => null, title: 'Imóvel', referrer: '' }
globalThis.localStorage = { getItem: () => saved }
globalThis.window = { location: { pathname: '/imoveis/1', href: 'https://site.test/imoveis/1' } }
globalThis.fetch = async (_url, options) => { sent.push(JSON.parse(options.body).navigation_event); return { ok: true } }
const tracker = new Tracker()
Object.assign(tracker, { startedAt: Date.now(), tracked: new Set(), canTrack: () => consent, consentAccepted: () => consent, searchParams: () => ({}), propertySnapshot: () => ({}) })
tracker.trackFavorites()
await tracker.requestQueue
assert.deepEqual(sent[0].favorite_ids, [])
// Rapid add/remove/add must deliver every state in order, including repeated snapshots.
for (const favorites of [[{id: 7}], [], [{id: 7}]]) {
  saved = JSON.stringify(favorites)
  tracker.trackFavorites()
}
await tracker.requestQueue
assert.deepEqual(sent.slice(1).map(item => item.favorite_ids), [['7'], [], ['7']])
tracker.trackFavorites()
consent = false // queued request must honor consent withdrawn before dispatch
await tracker.requestQueue
tracker.trackFavorites()
assert.equal(sent.length, 4)
console.log('Favoritos: estado inicial, alternância rápida, ordem e consentimento passaram.')
