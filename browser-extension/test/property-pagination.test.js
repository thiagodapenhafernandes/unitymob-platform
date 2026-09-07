import test from 'node:test';
import assert from 'node:assert/strict';
import {propertyPagination} from '../src/property-pagination.js';
test('shows ten at a time, reuses API pages, and stops at the final row',async()=>{
 const calls=[];const pager=propertyPagination(async({page})=>{calls.push(page);return {properties:Array.from({length:page===1?20:3},(_,i)=>(page-1)*20+i),more:page===1};});
 const first=await pager.load({page:1}); const second=await pager.load({page:2});const last=await pager.load({page:3});
 assert.equal(first.properties.length,10);assert.deepEqual(second.properties,[10,11,12,13,14,15,16,17,18,19]);assert.equal(last.properties.length,3);assert.equal(last.more,false);assert.deepEqual(calls,[1,2]);
});
test('reset discards cached results from a previous search',async()=>{
 let calls=0;const pager=propertyPagination(async()=>({properties:[++calls],more:false}));
 await pager.load({page:1});pager.reset();assert.deepEqual((await pager.load({page:1})).properties,[2]);
});
