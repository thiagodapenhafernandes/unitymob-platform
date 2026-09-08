import test from 'node:test';
import assert from 'node:assert/strict';
import {shareHistoryKey, readShareHistory, recordPropertyShare} from '../src/share-history.js';

test('isolates history by CRM, tenant, WhatsApp account, chat and lead', async()=>{
 const connection={origin:'https://crm.example.com',account:{tenant_id:1}};
 const context={account:'sender',chatId:'customer'};
 const key=await shareHistoryKey(connection,context,1);
 const alternatives=[
  [{...connection,origin:'https://another.example.com'},context,1],
  [{...connection,account:{tenant_id:2}},context,1],
  [connection,{...context,account:'another'},1],
  [connection,{...context,chatId:'another'},1],
  [connection,context,2]
 ];
 for(const args of alternatives)assert.notEqual(await shareHistoryKey(...args),key);
 assert.equal(await shareHistoryKey(connection,context,'1'),key);
});

test('persists counts per property across reads without changing other properties',async()=>{
 const data={};globalThis.chrome={storage:{local:{async get(key){return structuredClone({[key]:data[key]});},async set(value){Object.assign(data,structuredClone(value));}}}};
 assert.deepEqual(await readShareHistory('scope'),{});
 assert.equal((await recordPropertyShare('scope',7)).count,1);
 assert.equal((await recordPropertyShare('scope',7)).count,2);
 assert.equal((await recordPropertyShare('scope',8)).count,1);
 const saved=await readShareHistory('scope');
 assert.equal(saved[7].count,2);assert.equal(saved[8].count,1);
 assert.ok(Number.isFinite(Date.parse(saved[7].last_sent_at)));
 assert.deepEqual(await readShareHistory('another-scope'),{});
});
