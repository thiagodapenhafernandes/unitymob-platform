const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../../app/javascript/controllers/habitation_form_controller.js'), 'utf8')
  .replace(/^import .*\n/gm, '')
  .replace('export default class', 'globalThis.HabitationForm = class');
const context = vm.createContext({ Controller: class {} });
vm.runInContext(source, context);
const form = new context.HabitationForm();
assert.equal(form.pickCategoryValue('Condomínio', ['Condomínio', 'Empreendimento'], false, 'empreendimento'), 'Condomínio');
assert.equal(form.pickCategoryValue('Apartamento', ['Apartamento', 'Casa', 'Cobertura', 'Loft'], false, 'imoveis_residenciais'), 'Apartamento');
assert.equal(form.pickCategoryValue('Galpão', ['Apartamento', 'Casa'], true, 'imoveis_residenciais'), '');
console.log('OK: categoria escolhida preservada, inclusive Condomínio e Apartamento.');
