import test from 'node:test';
import assert from 'node:assert/strict';
import {preparePropertyPhoto, requestPropertyPhotoAccess} from '../src/property-preview.js';

test('requests only selected photo hosts synchronously and stops when access is denied', async () => {
  const previous = globalThis.chrome;
  let requested;
  globalThis.chrome = {permissions: {request(options) { requested = options; return Promise.resolve(true); }}};
  try {
    const pending = requestPropertyPhotoAccess(['https://cdn.saluteimoveis.com.br/a', 'https://cdn.saluteimoveis.com.br/b', '']);
    assert.deepEqual(requested, {origins: ['https://cdn.saluteimoveis.com.br/*']});
    await pending;
    requested = null;
    await requestPropertyPhotoAccess([]);
    assert.equal(requested, null);
    globalThis.chrome.permissions.request = async () => false;
    await assert.rejects(requestPropertyPhotoAccess(['https://cdn.example.com/a']), /preview_permission_required/);
    await assert.rejects(requestPropertyPhotoAccess(['http://cdn.example.com/a']), /preview_image_invalid/);
  } finally { globalThis.chrome = previous; }
});

test('prepares a JPEG thumbnail without credentials and closes the bitmap', async t => {
  let closed = false;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(options.credentials, 'omit');
    assert.equal(options.referrerPolicy, 'no-referrer');
    return new Response('photo', {headers:{'Content-Type':'image/jpeg'}});
  });
  const oldBitmap = globalThis.createImageBitmap, oldCanvas = globalThis.OffscreenCanvas;
  globalThis.createImageBitmap = async () => ({width:1280,height:720,close(){closed=true;}});
  globalThis.OffscreenCanvas = class {
    constructor(width,height){ assert.equal(width,320); assert.equal(height,180); this.width=width; this.height=height; }
    getContext(){return {drawImage(){}};}
    async convertToBlob(){return new Blob(['jpeg']);}
  };
  try { assert.equal(await preparePropertyPhoto('https://cdn.example.com/photo'),btoa('jpeg')); assert.equal(closed,true); }
  finally { globalThis.createImageBitmap=oldBitmap; globalThis.OffscreenCanvas=oldCanvas; }
});

test('rejects invalid URLs, network failures, and non-images', async t => {
  for (const url of ['invalid','http://example.com/photo','https://user:password@example.com/photo']) {
    await assert.rejects(preparePropertyPhoto(url), /preview_image_invalid/);
  }
  t.mock.method(globalThis,'fetch',async()=>{throw new Error('network');});
  await assert.rejects(preparePropertyPhoto('https://cdn.example.com/photo'),/preview_image_failed/);
  globalThis.fetch=async()=>new Response('<html>',{headers:{'Content-Type':'text/html'}});
  await assert.rejects(preparePropertyPhoto('https://cdn.example.com/photo'),/preview_image_failed/);
});

test('aborts a stalled download and reports preparation timeout', async t => {
  t.mock.timers.enable({apis:['setTimeout']});
  t.mock.method(globalThis,'fetch',async (_,options)=>new Promise((_,reject)=>options.signal.addEventListener('abort',()=>reject(new Error('aborted')))));
  const pending=preparePropertyPhoto('https://cdn.example.com/photo');
  t.mock.timers.tick(12000);
  await assert.rejects(pending,/preview_timeout/);
});
