import test from 'node:test';
import assert from 'node:assert/strict';
import {catalogSearchParams} from '../src/catalog-request.js';
test('catalog forwards allowed filters and drops caller tenant and SQL',()=>{
 assert.deepEqual(catalogSearchParams({filters:{category:['Casa','Apartamento'],bedrooms_min:'2',tenant_id:'42',sql:'DROP'}}),{bedrooms_min:'2',category:['Casa','Apartamento']});
});
test('catalog validates pagination, list size and parameter types',()=>{
 assert.throws(()=>catalogSearchParams({filters:{category:Array(31).fill('Casa')}}));
 assert.throws(()=>catalogSearchParams({filters:{min_price:{amount:1}}}));
 const params={catalog:true,facet:'mine',direction:'asc',order:'code',page:2,includeOptions:true};
 assert.equal(catalogSearchParams(params).page,2);
 assert.throws(()=>catalogSearchParams({...params,page:-1}));
});
