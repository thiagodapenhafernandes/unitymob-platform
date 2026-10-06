import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('column invitations preserve saved block order and appear only for empty columns', () => {
  const slots = [];
  const context = vm.createContext({ Controller: class {}, document: {
    createElement: () => ({ dataset: {}, append(button) { this.button = button; },
      after(node) { if (node.className === 'lp-column-slots') slots.push(node); } })
  } });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.element = { dataset: {} };
  const makeBlock = (type, column = '1') => ({
    dataset: { blockType: type }, classList: { toggle() {} },
    querySelectorAll: () => [],
    querySelector(selector) {
      this.fields ||= {};
      return this.fields[selector] ||= { value: selector.includes('[columns]') ? '2' : selector.includes('[column]') ? column : '',
        options: [], closest: () => ({}) };
    },
    after(node) {
      assert.equal(node.dataset?.blockType, undefined, "reindex must not regroup saved blocks by column");
      if (node.className === 'lp-column-slots') slots.push(node);
    }
  });
  const section = makeBlock('section');
  let children = [makeBlock('gallery', '2'), makeBlock('text', '1')];
  controller.liveBlocks = () => [section, ...children];
  controller.sectionMembers = () => [section, ...children];
  controller.positionOf = () => '0';
  controller.listTarget = { querySelectorAll: () => { slots.length = 0; return []; } };
  controller.emptyTarget = { querySelector: () => ({}) };

  controller.reindex();
  assert.equal(slots.length, 0);
  children = children.filter(block => block.dataset.blockType !== 'text');
  controller.reindex();
  assert.equal(slots.length, 1);
  assert.equal(slots[0].button.textContent, 'Coluna 1 · Adicionar bloco nesta coluna');
  children.push(makeBlock('text', '1'));
  controller.reindex();
  assert.equal(slots.length, 0);
});

test('section presets generate distinct Rails indexes and preserve each block data', () => {
  const fragments = [];
  const context = vm.createContext({ Controller: class {}, Date: { now: () => 100 }, document: {
    createElement: () => ({ content: {}, set innerHTML(value) { fragments.push(value); } }), dispatchEvent() {}
  }, Event: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.presetTargets = [{ dataset: { presetKey: 'steps' }, innerHTML: '<input name="blocks[__PRESET_0__][heading]" value="Etapas"><input id="__PRESET_0__"><input name="blocks[__PRESET_1__][items]" value="Conteúdo">' }];
  controller.listTarget = { append() {} };
  controller.reindex = () => {};
  controller.changed = () => {};
  controller.addPreset({ currentTarget: { dataset: { presetKey: 'steps' } } });
  controller.addPreset({ currentTarget: { dataset: { presetKey: 'steps' } } });
  assert.equal(fragments[0], '<input name="blocks[100][heading]" value="Etapas"><input id="100"><input name="blocks[101][items]" value="Conteúdo">');
  assert.match(fragments[1], /blocks\[102\]/);
  assert.match(fragments[1], /blocks\[103\]/);
});

test('only explicit submit persists and cancels pending preview work', () => {
  const context = vm.createContext({ Controller: class {}, clearTimeout() {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.finishEditing = () => {};
  let aborted = false;
  controller.abort = { abort() { aborted = true; } };
  controller.beforeSubmit();
  assert.equal(controller.submitting, true);
  assert.equal(aborted, true);
  assert.equal(controller.autosave, undefined);
  assert.equal(controller.queueAutosave, undefined);
});

test('inspector resize keyboard respects width limits', () => {
  const context = vm.createContext({ Controller: class {}, window: { innerWidth: 1000 } });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  let result;
  let width = 590;
  controller.element = { querySelector: () => ({ getBoundingClientRect: () => ({ width }) }), style: { setProperty: (_, value) => { result = value; } } };
  controller.resizeInspectorKey({ key: 'ArrowLeft', preventDefault() {} });
  assert.equal(result, '600px');
  width = 300;
  controller.resizeInspectorKey({ key: 'ArrowRight', preventDefault() {} });
  assert.equal(result, '300px');
});

test('changing a style applies it directly for elements and repeated rows', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.reindex = () => {};
  controller.saveStatus = () => {};
  controller.editing = true;
  controller.element = { dataset: {} };
  for (const [name, flag] of [
    ['page[blocks][0][data][element_title_text_color]', 'page[blocks][0][data][element_title_custom_colors]'],
    ['page[blocks][0][data][labels][2][border_radius]', 'page[blocks][0][data][labels][2][custom_border]']
  ]) {
    const input = { name: flag, value: 'false' };
    controller.schedule({ target: { name, closest: () => ({ querySelectorAll: () => [input] }) } });
    assert.equal(input.value, 'true');
  }
});

test('element ordering moves in both directions, persists keys and preserves containers', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  const parent = {};
  let elements = ['eyebrow', 'title', 'subtitle'].map(key => ({ key, node: { parentElement: parent,
    before() {}, after() {} } }));
  const input = { value: '' };
  controller.previewElements = () => elements;
  controller.schedule = () => {};
  controller.renderElementPanel = () => {};
  const card = { querySelector: () => input };
  controller.moveElement(card, 'title', 'subtitle');
  assert.equal(input.value, 'eyebrow,subtitle,title');
  elements = input.value.split(',').map(key => elements.find(item => item.key === key));
  controller.moveElement(card, 'title', 'eyebrow');
  assert.equal(input.value, 'title,eyebrow,subtitle');
  elements[0].node.parentElement = {};
  controller.moveElement(card, 'eyebrow', 'subtitle');
  assert.equal(input.value, 'title,eyebrow,subtitle');
});

test('ordering collection items moves their form rows without changing block element order', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  const parent = {};
  let moved = false, scheduled = false;
  const first = { key: 'items_0', node: { parentElement: parent }, formRow: { parentElement: parent } };
  const second = { key: 'items_1', node: { parentElement: parent }, formRow: { parentElement: parent, after(row) { moved = row === first.formRow; } } };
  controller.previewElements = () => [first, second];
  controller.schedule = () => { scheduled = true; };
  controller.moveElement({ querySelector() { throw new Error('must preserve block order'); } }, first.key, second.key);
  assert.equal(moved, true);
  assert.equal(scheduled, true);
});


test('style tabs classify appearance separately from typography and reveal only enabled effects', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  assert.equal(controller.styleField('element_text_font_family'), false);
  assert.equal(controller.styleField('element_text_background_mode'), true);
  const scope = { querySelectorAll: () => [{ name: 'row[element_text_background_mode]', value: 'transparent' }, { name: 'row[element_text_text_gradient]', value: 'false' }] };
  assert.equal(controller.fieldEffectVisible('element_text_gradient_color', scope), false);
  assert.equal(controller.fieldEffectVisible('element_text_text_gradient_color', scope), false);
  scope.querySelectorAll = () => [{ name: 'row[element_text_background_mode]', value: 'gradient' }];
  assert.equal(controller.fieldEffectVisible('element_text_gradient_color', scope), true);
});

test('compact multipart data preserves nested rows, arrays and files', () => {
  const context = vm.createContext({ Controller: class {}, Map });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  const entries = [
    ['landing_page[blocks_attributes][0][data][items][2][text]', '<p>Conteúdo</p>'],
    ['landing_page[blocks_attributes][0][data][items][2][element_text_font_weight]', '700'],
    ['landing_page[blocks_attributes][0][data][filters][city][]', 'Cidade A'],
    ['landing_page[blocks_attributes][0][data][filters][city][]', 'Cidade B'],
    ['landing_page[blocks_attributes][0][image_desktop]', { file: true }]
  ];
  const result = new Map();
  controller.compactFormData({ formData: { entries: () => entries, delete: name => result.delete(name), set: (name, value) => result.set(name, value) } });
  const payload = JSON.parse(result.get('landing_page[blocks_attributes][0][data_payload]'));
  assert.equal(payload.items['2'].text, '<p>Conteúdo</p>');
  assert.equal(payload.items['2'].element_text_font_weight, '700');
  assert.deepEqual(payload.filters.city, ['Cidade A', 'Cidade B']);
});


test('range sliders notify the named input and clamp values without a connect event', () => {
  const context = vm.createContext({ Controller: class {}, Event: class { constructor(type, options) { this.type = type; this.bubbles = options.bubbles; } } });
  vm.runInContext(readFileSync('app/javascript/controllers/ax_range_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Range = class'), context);
  const controller = new context.Range();
  const events = [];
  controller.rangeTarget = { min: '0', max: '64', value: '99' };
  controller.numberTarget = { value: '8', dispatchEvent: event => events.push(event) };
  controller.connect();
  assert.equal(events.length, 0);
  controller.rangeTarget.value = '99';
  controller.sync({ target: controller.rangeTarget });
  assert.equal(controller.numberTarget.value, 64);
  assert.equal(events[0].type, 'input');
  assert.equal(events[0].bubbles, true);
});


test('individual text style remains inside a visible row container and never shows card controls', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  const container = { dataset: { blockField: 'items' }, closest: () => null };
  const rowFields = ['text', 'background_color', 'element_text_text_color', 'element_text_font_family'].map(name => ({ dataset: {}, querySelector: selector => selector === 'trix-editor' ? null : { type: 'text', name: `page[items][0][${name}]` } }));
  controller.inspectedRow = { closest: () => container, querySelectorAll: selector => selector === '.ax-repeatable-rows__field' ? rowFields : [] };
  controller.inspectedItemKeys = ['text'];
  controller.inspectedFields = ['items'];
  const card = { querySelectorAll: () => [container] };
  controller.element = { dataset: {}, querySelector: () => card, querySelectorAll: () => [] };
  controller.organizeInspectorFields = () => {};
  controller.showInspectedGroups = () => {};
  controller.inspectorAppearance({ currentTarget: { dataset: { panel: 'appearance' } } });
  assert.equal(container.hidden, false);
  assert.deepEqual(rowFields.map(field => field.hidden), [true, true, false, true]);
  controller.inspectorAppearance({ currentTarget: { dataset: { panel: 'content' } } });
  assert.deepEqual(rowFields.map(field => field.hidden), [false, true, true, false]);
});

test('local style edits neither render remotely nor reindex the whole page', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.element = { dataset: {} };
  controller.saveStatus = () => {};
  controller.status = () => {};
  controller.reindex = controller.render = () => { throw new Error('must stay local'); };
  controller.applyLocalPreview = () => true;
  const control = { name: 'page[data][font_size]' };
  for (let i = 0; i < 100; i++) controller.schedule({ type: 'input', target: control });
  assert.equal(controller.localControls.size, 1);
  assert.equal(controller.dirty, true);
});

test('structural typing waits for field completion rather than fetching per key', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  controller.element = { dataset: {} };
  controller.saveStatus = controller.status = () => {};
  controller.applyLocalPreview = () => false;
  controller.reindex = controller.render = () => { throw new Error('must wait for change'); };
  controller.schedule({ type: 'input', target: { name: 'page[data][columns]' } });
});

test('local style calculator validates values and removes disabled effects on recalculation', () => {
  const context = vm.createContext({});
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_preview_style.js', 'utf8')
    .replace('export function', 'function') + '\nthis.style = previewStyle;', context);
  const styles = context.style({ background_mode: 'gradient', background_color: '#003344', gradient_color: '#b8972e', gradient_angle: '999', background_opacity: '50', backdrop_enabled: 'true', backdrop_blur: '100', backdrop_saturation: '500', font_family: 'url(evil)' });
  assert.equal(styles.background, 'linear-gradient(360deg,rgba(0,51,68,0.5),rgba(184,151,46,0.5))');
  assert.equal(styles['backdrop-filter'], 'blur(40px) saturate(200%)');
  assert.equal(styles['font-family'], undefined);
  assert.equal(context.style({ backdrop_enabled: 'false' })['backdrop-filter'], undefined);
  assert.equal(context.style({ background_mode: 'solid', background_color: 'red;display:none' }).background, undefined);
});
