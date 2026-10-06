import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function controller(file) {
  const context = vm.createContext({
    Controller: class {},
    window: { requestAnimationFrame: (callback) => callback() },
    Event: class {
      constructor(type, options = {}) {
        this.type = type;
        this.bubbles = options.bubbles;
      }
    },
    CustomEvent: class {
      constructor(type, options = {}) {
        this.type = type;
        this.detail = options.detail;
        this.bubbles = options.bubbles;
      }
    },
  });
  const source = readFileSync(`app/javascript/controllers/${file}_controller.js`, 'utf8')
    .replace(/^import[^\n]*\n/gm, '').replace('export default class', 'this.Subject = class');
  vm.runInContext(source, context);
  return new context.Subject();
}

function boliviaIti({ valid = false, number = '+59163595977' } = {}) {
  return {
    getSelectedCountryData: () => ({ iso2: 'bo', dialCode: '591' }),
    isValidNumber: () => valid,
    getNumber: () => number,
  };
}

function offlineBoliviaIti() {
  return {
    getSelectedCountryData: () => ({ iso2: 'bo', dialCode: '591' }),
    isValidNumber: () => { throw new Error('utils.js indisponível'); },
    getNumber: () => { throw new Error('utils.js indisponível'); },
  };
}

test('phone-input preserva o + do E.164 estrangeiro mesmo quando a lib marca inválido', () => {
  const subject = controller('phone_input');
  subject.iti = boliviaIti({ valid: false });
  subject.element = { value: '(63) 5959-77' };

  assert.equal(subject.normalizeForAjax('(63) 5959-77'), '+59163595977');
  assert.equal(subject.normalizeForSubmit('(63) 5959-77'), '+59163595977');
});

test('phone-input monta o E.164 pelo DDI quando o utils.js está indisponível', () => {
  const subject = controller('phone_input');
  subject.iti = offlineBoliviaIti();
  subject.element = { value: '(63) 5959-77' };

  assert.equal(subject.safeIsValidNumber(), false);
  assert.equal(subject.normalizeForAjax('(63) 5959-77'), '+59163595977');

  const detail = {};
  subject.handleMetadataRequest({ detail });
  assert.equal(detail.countryIso2, 'bo');
  assert.equal(detail.dialCode, '591');
  assert.equal(detail.e164, '+59163595977');
  assert.equal(detail.isValidNumber, false);
});

test('phone-input não duplica o DDI quando o valor já contém o código do país', () => {
  const subject = controller('phone_input');

  assert.equal(subject.joinDialCode('59163595977', '591'), '+59163595977');
  assert.equal(subject.joinDialCode('(63) 5959-77', '591'), '+59163595977');
  assert.equal(subject.joinDialCode('14155552671', '1'), '+14155552671');
});

test('phone-input mantém o comportamento brasileiro', () => {
  const subject = controller('phone_input');
  subject.iti = {
    getSelectedCountryData: () => ({ iso2: 'br', dialCode: '55' }),
    isValidNumber: () => true,
    getNumber: () => '+5547988516745',
  };
  subject.element = { value: '(47) 98851-6745' };

  assert.equal(subject.normalizeForAjax('(47) 98851-6745'), '5547988516745');
  assert.equal(subject.normalizeForSubmit('(47) 98851-6745'), '5547988516745');
  assert.equal(subject.bestEffortE164('(47) 98851-6745'), '+5547988516745');
});

test('seletor de proprietário aceita estrangeiro plausível mesmo com isValidNumber falso', () => {
  const subject = controller('habitation_owner_selector');
  subject.phoneMetadata = () => ({
    rawValue: '(63) 5959-77',
    countryIso2: 'bo',
    dialCode: '591',
    isValidNumber: false,
    e164: '+59163595977',
  });

  assert.equal(subject.phoneValidationError({ value: '(63) 5959-77' }), null);
});

test('seletor de proprietário rejeita estrangeiro curto demais', () => {
  const subject = controller('habitation_owner_selector');
  subject.phoneMetadata = () => ({
    rawValue: '12',
    countryIso2: 'bo',
    dialCode: '591',
    isValidNumber: false,
    e164: '',
  });

  assert.match(subject.phoneValidationError({ value: '12' }), /Selecione o país correto/);
});

test('seletor de proprietário usa o país do widget visível quando o phone-input ainda está no padrão', () => {
  const subject = controller('habitation_owner_selector');
  const field = {
    value: '(63) 5959-77',
    dispatchEvent(event) {
      if (event.type === 'phone-input:metadata') {
        event.detail.rawValue = field.value;
        event.detail.digits = '63595977';
        event.detail.countryIso2 = 'br';
        event.detail.isValidNumber = false;
        event.detail.e164 = '';
      }
      if (event.type === 'phone-input:normalize') {
        event.detail.value = '963595977';
      }
    },
    _habitationOwnerIntlTelInput: boliviaIti({ valid: false }),
  };

  const metadata = subject.phoneMetadata(field);
  assert.equal(metadata.countryIso2, 'bo');
  assert.equal(metadata.e164, '+59163595977');
  assert.equal(subject.phoneValidationError(field), null);
  assert.equal(subject.normalizedPhoneValue(field), '+59163595977');
});

test('seletor de proprietário aceita segundo telefone vazio e valida quando preenchido', () => {
  const subject = controller('habitation_owner_selector');
  subject.createNameTarget = { value: 'Dono' };
  subject.createPhoneTarget = { value: '(47) 98851-6745' };
  subject.createPhone2Target = { value: '', focus() {} };
  subject.createCityTarget = { value: 'Itajaí' };
  subject.phoneMetadata = (field) => (
    field.value === '123'
      ? { rawValue: '123', countryIso2: 'br', isValidNumber: false, e164: '' }
      : { rawValue: '(47) 98851-6745', countryIso2: 'br', isValidNumber: true, e164: '+5547988516745' }
  );
  let shown = null;
  subject.showError = (message) => { shown = message; };
  subject.clearError = () => { shown = null; };

  assert.equal(subject.validateQuickFields('create'), true);
  assert.equal(shown, null);

  subject.createPhone2Target.value = '123';
  assert.equal(subject.validateQuickFields('create'), false);
  assert.match(shown, /Telefone inválido/);
});

test('seletor de proprietário preenche o segundo telefone na edição', () => {
  const subject = controller('habitation_owner_selector');
  const field = (value = '') => ({
    value,
    dispatchEvent() {},
    closest() { return {}; },
    focus() {},
  });
  subject.createPanelTarget = { hidden: true };
  subject.editPanelTarget = { hidden: true };
  subject.editNameTarget = field();
  subject.editPhoneTarget = field();
  subject.editPhone2Target = field();
  subject.editEmailTarget = field();
  subject.editCityTarget = field();
  subject.clearError = () => {};

  subject.showEditPanel({
    name: 'Dono',
    phone_primary: '5547999991111',
    phone_secondary: '5548988882222',
    phone_secondary_display: '55 (48) 98888-2222',
    email: '',
    city: 'Itajaí',
  });

  assert.equal(subject.editPhone2Target.value, '55 (48) 98888-2222');
});

test('seletor de proprietário monta o E.164 do widget visível sem utils.js', () => {
  const subject = controller('habitation_owner_selector');
  const field = {
    value: '59163595977',
    dispatchEvent(event) {
      if (event.type === 'phone-input:metadata') {
        event.detail.rawValue = field.value;
        event.detail.countryIso2 = 'br';
        event.detail.isValidNumber = false;
        event.detail.e164 = '';
      }
      if (event.type === 'phone-input:normalize') {
        event.detail.value = '5559163595977';
      }
    },
    _habitationOwnerIntlTelInput: offlineBoliviaIti(),
  };

  assert.equal(subject.normalizedPhoneValue(field), '+59163595977');
});
