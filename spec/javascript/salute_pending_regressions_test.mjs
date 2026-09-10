import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function controller(file) {
  const context = vm.createContext({ Controller: class {} });
  const source = readFileSync(`app/javascript/controllers/${file}_controller.js`, 'utf8')
    .replace(/^import[^\n]*\n/gm, '').replace('export default class', 'this.Subject = class');
  vm.runInContext(source, context);
  return new context.Subject();
}

test('organizar libera o botão depois de sucesso e falha e permite repetir', async () => {
  const subject = controller('media_tools');
  subject.canEditValue = subject.hasOrganizeUrlValue = true;
  subject.replaceGallery = () => {};
  subject.reportError = () => {};
  subject.setBusy = (button, busy) => { if (button) button.disabled = busy; };
  for (const fail of [false, true, false]) {
    const button = { disabled: false };
    const event = { currentTarget: button };
    subject.requestJson = async () => {
      // DOM currentTarget only lives during dispatch, not across await.
      event.currentTarget = null;
      if (fail) throw new Error('offline');
      return {};
    };
    await subject.organize(event);
    assert.equal(button.disabled, false);
  }
});

test('apenas o gerenciador que abriu o modal compartilhado trata sua exclusão', () => {
  const active = controller('attribute_manager');
  const inactive = controller('attribute_manager');
  const modal = { attributeManagerController: active };
  active.modalElement = inactive.modalElement = modal;
  let calls = 0;
  active.delete = () => calls++;
  inactive.delete = () => assert.fail('Gerenciador de outra categoria recebeu exclusão');
  const button = {};
  const event = {
    target: { closest: selector => selector.includes("'delete'") ? button : null },
    preventDefault() {}, stopPropagation() {}
  };
  inactive.handleModalClick(event);
  active.handleModalClick(event);
  assert.equal(calls, 1);
});

test('DDD 55 é preservado no cadastro do proprietário e normalizado no site', () => {
  const owner = controller('habitation_owner_selector');
  assert.equal(owner.brazilianNationalDigits('55999991234'), '55999991234');
  assert.equal(owner.brazilianNationalDigits('5555999991234'), '55999991234');
  const lead = controller('lead_capture');
  assert.equal(lead.normalizePhone('(55) 9999-1234'), '5555999991234');
  assert.equal(lead.normalizePhone('(55) 3333-1234'), '555533331234');
});
