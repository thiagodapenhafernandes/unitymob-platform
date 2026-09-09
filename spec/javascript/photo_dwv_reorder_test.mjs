import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

test('reorder replaces stale DWV indices with the saved gallery before the next action', async () => {
  const context = vm.createContext({ Controller: class {} });
  const source = readFileSync('app/javascript/controllers/photo_upload_controller.js', 'utf8')
    .replace(/import[\s\S]*?from "[^"]+"\n/g, '').replace('export default class', 'this.Upload = class');
  vm.runInContext(source, context);
  const controller = new context.Upload();
  let indices = ['2', '0', '1'];
  controller.hasApiOrderInputTarget = controller.hasPreviewContainerTarget = true;
  controller.apiOrderInputTarget = { value: indices.join(',') };
  controller.previewContainerTarget = {
    querySelectorAll: selector => selector === '.api-picture-item' ? indices.map(apiIndex => ({ dataset: { apiIndex } })) : [],
    set innerHTML(html) { assert.equal(html, 'saved gallery'); indices = ['0', '1', '2']; }
  };
  controller.selectedNewFiles = [];
  controller.application = { getControllerForElementAndIdentifier() {} };
  controller.canSyncReorder = () => true;
  for (const name of ['updateWatermarkStatus', 'refreshMediaDragAndDrop', 'syncSiteVisibilityControls', 'refreshPhotoBadges', 'updateMediaCounts']) controller[name] = () => {};
  controller.showTransientFeedback = message => assert.fail(message);
  controller.requestJson = async (_url, options) => {
    assert.equal(options.json.habitation.ordered_picture_indices, '2,0,1');
    return { gallery_html: 'saved gallery', inputs: { ordered_picture_indices: '0,1,2' } };
  };
  await controller.syncReorder();
  assert.deepEqual(indices, ['0', '1', '2']);
  assert.equal(controller.apiOrderInputTarget.value, '0,1,2');
});
