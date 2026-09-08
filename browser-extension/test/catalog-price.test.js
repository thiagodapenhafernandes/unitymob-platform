import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {catalogSearchParams} from '../src/catalog-request.js';
const currency=await readFile(new URL('../../app/javascript/lib/currency_filter.js',import.meta.url),'utf8');
const source=(await readFile(new URL('../../app/javascript/lib/catalog_controls.js',import.meta.url),'utf8'))
 .replace("import TomSelect from '../vendor/tom-select.js';",'')
 .replace("import {formatCurrencyFilter,currencyFilterDigits} from './currency_filter.js';",currency);
const {maskCatalogPrice,catalogPriceValue,restoreFilters,enhanceFilters,readFilters,filterMarkup}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('catalog renders paired ranges and all supplied account amenities safely',()=>{
 const features=Array.from({length:45},(_,i)=>`Característica ${i}`);
 const html=filterMarkup([],{amenity_features:features,amenity_infrastructure:['Salão de festas','<script>']});
 assert.equal((html.match(/class="pc-range-pair"/g)||[]).length,7);
 for(const feature of features)assert.ok(html.includes(`value="${feature}"`));
 assert.ok(html.includes('value="Salão de festas"'));
 assert.ok(html.includes('&lt;script&gt;'));
 assert.ok(!html.includes('<script>'));
});
test('admin whole-reais mask does not introduce cents or multiply pasted prices',()=>{
 for(const value of ['3200000','3.200.000','R$ 3.200.000,00']) {
  assert.equal(maskCatalogPrice(value),'3.200.000');
  assert.equal(maskCatalogPrice(maskCatalogPrice(value),true),'3.200.000');
  assert.equal(catalogPriceValue(maskCatalogPrice(value)),'3200000');
 }
 assert.equal(maskCatalogPrice(''),'');
 assert.equal(catalogPriceValue(''),'');
});
test('typing, blur, apply, API parameters and repeated restore preserve the three-million range',()=>{
 const inputs=['min_price','max_price'].map(name=>({name,value:'',setCustomValidity(){},hasAttribute:key=>key==='data-price',setSelectionRange(start){this.selectionStart=start;}}));
 const form={reset(){inputs.forEach(i=>i.value='');},querySelectorAll(selector){return selector==='[data-enhance]'?[]:inputs;}};
 enhanceFilters(form);
 inputs.forEach((input,i)=>{input.value=i?'3.200.000':'3.000.000';input.selectionStart=input.value.length;input.oninput();input.onblur();});
 const NativeFormData=globalThis.FormData;
 globalThis.FormData=class {constructor(){this.data=new Map(inputs.map(i=>[i.name,i.value]));}keys(){return this.data.keys();}getAll(key){return [this.data.get(key)];}};
 try {
  for(let n=0;n<3;n++) {
   const values=readFilters(form);
   assert.deepEqual(catalogSearchParams({filters:values}),{min_price:'3000000',max_price:'3200000'});
   restoreFilters(form,JSON.parse(JSON.stringify(values)));
   assert.deepEqual(inputs.map(i=>i.value),['3.000.000','3.200.000']);
  }
  restoreFilters(form,{min_price:'3000000.00',max_price:'3200000.00'});
  assert.deepEqual(inputs.map(i=>i.value),['3.000.000','3.200.000']);
  restoreFilters(form,{});assert.deepEqual(inputs.map(i=>i.value),['','']);
 } finally {globalThis.FormData=NativeFormData;}
});
