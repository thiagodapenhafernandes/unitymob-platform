import test from 'node:test';
import assert from 'node:assert/strict';
import { createPropertyGallery } from '../src/property-gallery.js';

test('gallery retains decoded photo while pending, after errors and stale requests', async () => {
  const pending = new Map();
  class Node {
    children = []; attrs = {}; listeners = {}; isConnected = true;
    constructor(tag) { this.tag = tag; }
    append(...nodes) { for (const node of nodes) { node.remove(); node.parent = this; this.children.push(node); } }
    remove() { if (this.parent) this.parent.children = this.parent.children.filter(n => n !== this); }
    setAttribute(k, v) { this.attrs[k] = v; }
    removeAttribute(k) { delete this.attrs[k]; }
    addEventListener(k, fn) { this.listeners[k] = fn; }
    showModal() { this.open = true; }
    close() { this.open = false; this.listeners.close(); }
    scrollIntoView() {}
    focus() {}
  }
  const original = { document: globalThis.document, Image: globalThis.Image, matchMedia: globalThis.matchMedia };
  globalThis.document = { activeElement: new Node('button'), body: new Node('body'), createElement: tag => new Node(tag) };
  globalThis.Image = class extends Node {
    constructor() { super('img'); }
    decode() { return new Promise((resolve, reject) => pending.set(this.src, { resolve, reject })); }
  };
  globalThis.matchMedia = () => ({ matches: true });
  const tick = () => new Promise(resolve => setImmediate(resolve));
  try {
    const dialog = createPropertyGallery(['a', 'b', 'c', 'd'], 'Imóvel');
    const stage = dialog.children[1], canvas = stage.children[0];
    const thumbs = dialog.children[2].children[2];
    pending.get('a').resolve(); await tick();
    const first = canvas.children[0];
    thumbs.children[1].onclick(); await tick();
    assert.equal(canvas.children[0], first, 'current photo remains while next decodes');
    pending.get('b').reject(new Error('offline')); await tick();
    assert.equal(canvas.children[0], first, 'failed load keeps current photo');
    thumbs.children[2].onclick(); thumbs.children[3].onclick();
    pending.get('c').resolve(); await tick();
    assert.equal(canvas.children[0], first, 'stale response cannot replace photo');
    pending.get('d').resolve(); await tick();
    assert.equal(canvas.children[0].src, 'd');
    assert.equal(canvas.children.length, 1);
    thumbs.children[1].onclick(); dialog.close();
    pending.get('b').resolve(); await tick();
    assert.equal(canvas.children[0].src, 'd', 'closed gallery ignores pending load');
  } finally { Object.assign(globalThis, original); }
});
