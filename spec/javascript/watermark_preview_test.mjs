import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function setup({ source = '/saved.png', complete = true, naturalWidth = 300, placeholder = true } = {}) {
  const revoked = [];
  const context = vm.createContext({ ResizeObserver: class { observe() {} disconnect() {} }, Controller: class {}, URL: {
    createObjectURL: () => 'blob:preview', revokeObjectURL: value => revoked.push(value)
  } });
  vm.runInContext(readFileSync('app/javascript/controllers/watermark_preview_controller.js', 'utf8')
    .replace(/^import .*\n/, '').replace('export default class', 'this.Preview = class'), context);
  const controller = new context.Preview();
  function element() {
    const classes = new Set();
    return { hidden: false, textContent: '', style: { setProperty() {} }, classList: {
      add: (...values) => values.forEach(value => classes.add(value)),
      remove: (...values) => values.forEach(value => classes.delete(value)),
      toggle: (value, enabled) => enabled ? classes.add(value) : classes.delete(value),
      contains: value => classes.has(value)
    } };
  }
  const logo = Object.assign(element(), { complete, naturalWidth,
    getAttribute: () => source, removeAttribute: () => { source = null; }
  });
  Object.defineProperty(logo, 'src', { get: () => source, set: value => { source = value; logo.complete = false; logo.naturalWidth = 0; } });
  const targets = {
    logo, placeholder: element(), placeholderTitle: element(), placeholderMessage: element(),
    removeInput: { checked: false }, fileInput: { files: [] }, frame: element(),
    sizeInput: { value: '28' }, opacityInput: { value: '70' }, sizeValue: element(), opacityValue: element()
  };
  for (const [name, value] of Object.entries(targets)) {
    controller[`${name}Target`] = value;
    controller[`has${name[0].toUpperCase()}${name.slice(1)}Target`] = true;
  }
  controller.hasPlaceholderTarget = placeholder;
  controller.positionInputTargets = [{ checked: true, value: 'center' }];
  controller.connect();
  const loaded = () => { logo.complete = true; logo.naturalWidth = 300; controller.imageLoaded(); };
  return { controller, ...targets, revoked, loaded };
}

test('cached image and sliders remain visible and synchronized', () => {
  const env = setup();
  assert.equal(env.logo.hidden, false);
  assert.equal(env.placeholder.hidden, true);
  assert.equal(env.logo.style.width, '28%');
  assert.equal(env.logo.style.opacity, 0.7);
  assert.ok(env.logo.classList.contains('watermark-position-center'));
  env.sizeInput.value = '40'; env.opacityInput.value = '50'; env.controller.update();
  assert.equal(env.logo.style.width, '40%');
  assert.equal(env.opacityValue.textContent, '50%');
});

test('missing source, loading image and failed cached image have distinct fallback states', () => {
  const empty = setup({ source: null });
  assert.equal(empty.logo.hidden, true);
  assert.equal(empty.placeholderTitle.textContent, 'Envie uma imagem');
  const loading = setup({ complete: false, naturalWidth: 0 });
  assert.equal(loading.placeholderTitle.textContent, 'Carregando prévia');
  loading.loaded();
  assert.equal(loading.logo.hidden, false);
  const broken = setup({ naturalWidth: 0 });
  assert.equal(broken.placeholderTitle.textContent, 'Não foi possível carregar a imagem');
  assert.equal(broken.logo.hidden, true);
});

test('removal can be reversed without losing the loaded image or position', () => {
  const env = setup();
  env.removeInput.checked = true; env.controller.update();
  assert.equal(env.logo.hidden, true);
  assert.equal(env.placeholderTitle.textContent, 'Marca será removida ao salvar');
  env.removeInput.checked = false; env.controller.update();
  assert.equal(env.logo.hidden, false);
  assert.equal(env.logo.src, '/saved.png');
});

test('upload cancels removal; clearing file restores saved source and frees object URL', () => {
  const env = setup();
  env.removeInput.checked = true;
  env.fileInput.files = [{}]; env.controller.loadFile();
  assert.equal(env.removeInput.checked, false);
  assert.equal(env.logo.src, 'blob:preview');
  env.loaded(); assert.equal(env.logo.hidden, false);
  env.fileInput.files = []; env.controller.loadFile();
  assert.equal(env.logo.src, '/saved.png');
  assert.deepEqual(env.revoked, ['blob:preview']);
  env.loaded(); assert.equal(env.logo.hidden, false);
});

test('failed upload can be replaced, and clearing the first upload restores empty state', () => {
  const env = setup({ source: null });
  env.fileInput.files = [{}]; env.controller.loadFile(); env.controller.imageFailed();
  assert.equal(env.placeholderTitle.textContent, 'Não foi possível carregar a imagem');
  env.controller.loadFile(); env.loaded(); assert.equal(env.logo.hidden, false);
  env.fileInput.files = []; env.controller.loadFile();
  assert.equal(env.logo.hidden, true);
  assert.equal(env.placeholderTitle.textContent, 'Envie uma imagem');
});

test('missing placeholder does not break preview or disposal', () => {
  const env = setup({ placeholder: false });
  env.fileInput.files = [{}]; env.controller.loadFile(); env.loaded();
  assert.equal(env.logo.hidden, false);
  env.controller.disconnect();
  assert.deepEqual(env.revoked, ['blob:preview']);
});
