import test from 'node:test';
import assert from 'node:assert/strict';
import {searchCatalog} from '../preview/catalog.js';
test('preview combines price, category and minimum rooms',()=>{
 const rows=searchCatalog({filters:{max_price:'800000',category:'Apartamento',bedrooms:'3'}});
 assert.deepEqual(rows.map(p=>p.id),['2310']);
});
test('preview searches accented locations and separates rental prices',()=>{
 assert.deepEqual(searchCatalog({query:'nacoes'}).map(p=>p.id),['3100']);
 assert.deepEqual(searchCatalog({purpose:'locacao',filters:{max_price:'3000'}}).map(p=>p.id),['4300']);
});
test('preview supports empty results, quick filters and linked flags',()=>{
 assert.equal(searchCatalog({filters:{quick:'frente_mar',max_price:'500000'}}).length,0);
 assert.equal(searchCatalog({query:'1842'},new Set(['1842']))[0].linked,true);
});
