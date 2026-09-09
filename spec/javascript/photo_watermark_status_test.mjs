import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function setup() {
  const context = vm.createContext({ Controller: class {}, AbortController, setTimeout, clearTimeout, FormData: class { append() {} }, URL: { revokeObjectURL() {} } });
  const source = readFileSync('app/javascript/controllers/photo_upload_controller.js', 'utf8')
    .replace(/import[\s\S]*?from "[^"]+"\n/g, '').replace('export default class', 'this.Upload = class');
  vm.runInContext(source, context);
  const controller = new context.Upload();
  controller.selectedNewFiles = [];
  controller.setFeedbackText = () => {};
  controller.showProgressFeedback = () => {};
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

test('uploads drain new additions and isolate a failed file for retry', async () => {
  const controller = setup();
  const a = { id: 'a', file: { name: 'a.jpg' } }, b = { id: 'b', file: { name: 'b.jpg' } };
  controller.selectedNewFiles = [a];
  controller.canSyncUpload = () => true;
  controller.setBusyState = () => {};
  controller.showProgressFeedback = () => {};
  controller.setFeedbackText = () => {};
  controller.showProgressFeedback = () => {};
  controller.setPhotoUploadState = () => {};
  controller.syncInputFilesFromState = () => {};
  controller.element = { querySelector: () => ({ checked: true }) };
  controller.previewContainerTarget = { querySelector: () => ({ remove() {} }) };
  let attempts = 0;
  controller.requestJsonWithProgress = async () => {
    attempts++;
    if (attempts === 1) { controller.selectedNewFiles.push(b); throw new Error('failed'); }
    return { photos: [], watermark_photos: [] };
  };
  await controller.uploadNewFiles([a]);
  assert.equal(attempts, 2);
  assert.equal(controller.selectedNewFiles.length, 1);
  assert.equal(controller.selectedNewFiles[0], a);
  assert.equal(a.failed, true);
  assert.equal(controller.uploadInProgress, false);
  a.failed = false;
  await controller.uploadNewFiles([a]);
  assert.equal(attempts, 3);
  assert.equal(controller.selectedNewFiles.length, 0);
});

test('summary counts confirmed completions and does not turn failure into success', () => {
  const controller = setup();
  let summary;
  controller.showProgressFeedback = (...args) => { summary = args; };
  controller.updateWatermarkStatus({ photos: [], watermark_photos: [{id: 2, phase: 'saving'}, {id: 3, phase: 'processing', status: 'failed'}] });
  assert.equal(summary[0], '0 de 2 fotos salvas · 1 com falha');
  assert.equal(summary[1], 62);
  controller.updateWatermarkStatus({ photos: [{id: 2}], watermark_photos: [{id: 3, phase: 'processing', status: 'failed'}] });
  assert.equal(summary[0], '1 de 2 fotos salvas · 1 com falha');
  assert.equal(summary[1], 75);
  controller.updateWatermarkStatus({ photos: [{id: 2}, {id: 3}], watermark_photos: [] });
  assert.equal(summary[1], 100);
  assert.equal(summary[2], 'success');
  assert.equal(summary[0], '2 fotos salvas com marca d’água. Tudo pronto!');
  controller.processingProgress = new Map([['4', {percent: 100}]]);
  controller.renderProcessingSummary();
  assert.equal(summary[0], '1 foto salva. Tudo pronto!');
});
