import test from 'node:test';
import assert from 'node:assert/strict';
import {catalog} from '../preview/catalog.js';
import {filterWorkspace} from '../preview/property-workspace.js';
test('workspace combines facet with filters and does not mutate the source',()=>{
 const ids=catalog.map(p=>p.id);
 assert.deepEqual(filterWorkspace(catalog,{facet:'venda',filters:{category:'Apartamento',max_price:'800000',bedrooms:'3'}}).map(p=>p.id),['2310']);
 assert.deepEqual(catalog.map(p=>p.id),ids);
});
test('workspace handles all, rental, owned and opportunity facets',()=>{
 assert.equal(filterWorkspace(catalog).length,8);
 assert.equal(filterWorkspace(catalog,{facet:'locacao'}).length,2);
 const sample=catalog.map((p,i)=>({...p,mine:i===0,opportunity:i===1}));
 assert.deepEqual(filterWorkspace(sample,{facet:'mine'}).map(p=>p.id),['1842']);
 assert.deepEqual(filterWorkspace(sample,{facet:'opportunity'}).map(p=>p.id),['2310']);
});
test('workspace sorts numeric prices and supports zero results',()=>{
 assert.equal(filterWorkspace(catalog,{facet:'venda',order:'price_desc'})[0].id,'1405');
 assert.equal(filterWorkspace(catalog,{facet:'venda',order:'price_asc'})[0].id,'1842');
 assert.equal(filterWorkspace(catalog,{query:'inexistente'}).length,0);
});
test('workspace reverses numeric code ordering without changing the source',()=>{
 const items=[{code:'2'},{code:'10'},{code:'1'}];
 assert.deepEqual(filterWorkspace(items,{order:'code',direction:'asc'}).map(p=>p.code),['1','2','10']);
 assert.deepEqual(filterWorkspace(items,{order:'code',direction:'desc'}).map(p=>p.code),['10','2','1']);
 assert.deepEqual(items.map(p=>p.code),['2','10','1']);
});
test('workspace combines multiple selections with minimum and maximum characteristics',()=>{
 const items=[
  {id:'a',category:'Casa',city:'Itajaí',bedrooms:2,area:80},
  {id:'b',category:'Apartamento',city:'Itajaí',bedrooms:3,area:110},
  {id:'c',category:'Apartamento',city:'Camboriú',bedrooms:4,area:160}
 ];
 assert.deepEqual(filterWorkspace(items,{filters:{category:['Casa','Apartamento'],city:['Itajaí'],bedrooms_min:'3',bedrooms_max:'4',area_max:'120'}}).map(p=>p.id),['b']);
});
