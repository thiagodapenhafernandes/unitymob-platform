import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function setup() {
  const context = vm.createContext({ Controller: class {}, AbortController, setTimeout, clearTimeout });
  const source = readFileSync('app/javascript/controllers/photo_upload_controller.js', 'utf8')
    .replace(/import[\s\S]*?from "[^"]+"\n/g, '').replace('export default class', 'this.Upload = class');
  vm.runInContext(source, context);
  const controller = new context.Upload();
  controller.selectedNewFiles = [];
  controller.watermarkPhotoSignature = '1';
  controller.hasWatermarkStatusTarget = true;
  controller.watermarkStatusTarget = { innerHTML: '' };
  controller.scheduleWatermarkPoll = () => { controller.scheduled = true; };
  controller.applyMediaPayload = payload => { controller.applied = payload; controller.updateWatermarkStatus(payload); };
  return controller;
}

test('polling refreshes the gallery when a processed photo becomes available', async () => {
  const controller = setup();
  const payload = { photos: [{ id: 1 }, { id: 2 }], watermark_photos: [], watermark_html: '' };
  controller.requestJson = async () => payload;
  await controller.pollWatermark();
  assert.equal(controller.applied, payload);
  assert.equal(controller.watermarkPhotoSignature, '1,2');
});

test('pending work updates status without replacing an unchanged gallery', async () => {
  const controller = setup();
  controller.requestJson = async () => ({ photos: [{ id: 1 }], watermark_photos: [{ status: 'retrying' }], watermark_html: 'Tentando novamente' });
  await controller.pollWatermark();
  assert.equal(controller.applied, undefined);
  assert.equal(controller.watermarkStatusTarget.innerHTML, 'Tentando novamente');
  assert.equal(controller.scheduled, true);
});

test('polling waits while the user has selected files or is uploading', async () => {
  const controller = setup();
  controller.selectedNewFiles = [{}];
  controller.requestJson = () => { throw new Error('must not fetch'); };
  await controller.pollWatermark();
  assert.equal(controller.scheduled, true);
});

test('a final failure stops polling and a late response does not update a disconnected page', async () => {
  const controller = setup();
  controller.updateWatermarkStatus({ watermark_photos: [{ status: 'failed' }], watermark_html: 'Falhou' });
  assert.equal(controller.scheduled, undefined);
  controller.requestJson = async () => { controller.watermarkDisconnected = true; return { photos: [{ id: 2 }] }; };
  await controller.pollWatermark();
  assert.equal(controller.applied, undefined);
});
