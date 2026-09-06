import test from 'node:test';
import assert from 'node:assert/strict';
import { authorizeInTab } from '../src/auth-tab.js';

test('fallback accepts only its own tab and exact callback, and removes listeners', async () => {
 let update, removed, closed;
 global.chrome = {tabs:{
  onUpdated:{addListener(fn){update=fn;},removeListener(fn){assert.equal(fn,update);update=null;}},
  onRemoved:{addListener(fn){removed=fn;},removeListener(fn){assert.equal(fn,removed);removed=null;}},
  async create(){return {id:9};},async get(){return {id:9,url:'https://crm.example/login'};},async remove(id){closed=id;}
 }};
 const result=authorizeInTab('https://crm.example/login','https://extension.chromiumapp.org/unitymob');
 await new Promise(resolve=>setImmediate(resolve));
 update(1,{url:'https://extension.chromiumapp.org/unitymob?state=wrong'});
 update(9,{url:'https://evil.example/unitymob'});
 assert.ok(update);
 const url='https://extension.chromiumapp.org/unitymob?state=expected&login_token=code';
 update(9,{url});
 assert.equal(await result,url); assert.equal(closed,9); assert.equal(update,null); assert.equal(removed,null);
});
