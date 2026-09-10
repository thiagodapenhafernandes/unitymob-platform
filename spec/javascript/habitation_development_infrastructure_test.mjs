import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

const context = vm.createContext({ Controller: class {}, Event });
vm.runInContext(readFileSync('app/javascript/controllers/habitation_form_controller.js', 'utf8')
  .replace(/^import[^\n]*\n/gm, '').replace('export default class', 'this.Subject = class'), context);

test('vínculo soma infraestrutura, respeita bloqueios e não reaplica ao abrir edição', () => {
  const subject = new context.Subject();
  const changes = [];
  const inputs = [
    { value: 'Jardim', checked: true },
    { value: 'Elevador', checked: false },
    { value: 'Piscina coletiva', checked: false, disabled: true }
  ].map(input => ({ ...input, dispatchEvent(event) { changes.push([this.value, event.type, event.bubbles]); } }));
  subject.element = { querySelectorAll: () => inputs };
  subject.hasDevelopmentSelectTarget = true;
  subject.developmentSelectTarget = { value: '100' };
  subject.developmentsValue = { '100': { infra_estrutura: ['Elevador', 'Piscina coletiva'] } };
  for (const method of ['toggleDevelopmentNameReadonly', 'syncDevelopmentEditLink',
    'syncDevelopmentRelationshipFields', 'syncDevelopmentAddressFields', 'enableDevelopmentPhotosFallback']) subject[method] = () => {};

  subject.syncFromDevelopmentSelection();
  assert.equal(inputs[1].checked, false);
  subject.developmentChanged();
  assert.deepEqual(inputs.map(input => input.checked), [true, true, false]);
  assert.deepEqual(changes, [['Elevador', 'change', true]]);
  subject.developmentChanged();
  assert.equal(changes.length, 1);
  inputs[1].checked = false;
  subject.newRecordValue = true;
  subject.syncFromDevelopmentSelection();
  assert.equal(inputs[1].checked, true);
});
