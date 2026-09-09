import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync('app/javascript/lib/lead_attribution.js', 'utf8');
const { LeadAttribution } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
function storage() { const data = new Map(); return {getItem: k=>data.get(k) || null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k),data}; }
function browser() { return {location:new URL('https://site.test/?gclid=first'),localStorage:storage(),sessionStorage:storage()}; }
function document(referrer='https://google.com/') {return {cookie:'unitymob_lgpd_consent=accepted',referrer};}

test('first touch survives a later TikTok conversion without mixing click IDs',()=>{
 const b=browser(), d=document(); let now=0;
 new LeadAttribution(b,d,()=>now);
 now+=86400000;b.location=new URL('https://site.test/?ttclid=last');d.referrer='https://tiktok.com/';
 const payload=new LeadAttribution(b,d,()=>now).payload();
 assert.equal(payload.first_touch.gclid,'first');assert.equal(payload.conversion_touch.ttclid,'last');
 assert.equal(payload.gclid,undefined);
});
test('internal navigation retains the arrival of the conversion session',()=>{
 const b=browser(),d=document();new LeadAttribution(b,d,()=>0);
 b.location=new URL('https://site.test/imovel');d.referrer='https://site.test/';
 assert.equal(new LeadAttribution(b,d,()=>100).payload().conversion_touch.gclid,'first');
});
test('a direct visit after session expiry does not inherit an old paid session',()=>{
 const b=browser(),d=document();new LeadAttribution(b,d,()=>0);
 b.location=new URL('https://site.test/imovel');d.referrer='';
 const p=new LeadAttribution(b,d,()=>31*60000).payload();
 assert.equal(p.gclid,undefined);assert.equal(p.first_touch.gclid,'first');
});
test('session refresh does not extend the ninety-day first touch window',()=>{
 const b=browser(),d=document();new LeadAttribution(b,d,()=>0);
 const first=b.localStorage.getItem('unitymob_first_touch_attribution_v1');
 new LeadAttribution(b,d,()=>1000).payload();assert.equal(b.localStorage.getItem('unitymob_first_touch_attribution_v1'),first);
});
test('pending consent keeps attribution in memory without browser persistence',()=>{
 const b=browser(),d=document();d.cookie='';const a=new LeadAttribution(b,d);
 assert.equal(a.payload().gclid,'first');assert.equal(b.localStorage.data.size,0);assert.equal(b.sessionStorage.data.size,0);
});
test('rejection discards prior storage and attribution',()=>{
 const b=browser(),d=document();const a=new LeadAttribution(b,d);d.cookie='unitymob_lgpd_consent=rejected';
 assert.deepEqual(a.payload(),{});assert.equal(b.localStorage.data.size,0);assert.equal(b.sessionStorage.data.size,0);
});
test('private browsing and corrupt storage cannot block lead capture',()=>{
 const b=browser(),d=document();Object.defineProperty(b,'localStorage',{get(){throw new Error('blocked')}});
 b.sessionStorage.setItem('unitymob_conversion_touch_v2','broken json');
 assert.equal(new LeadAttribution(b,d).payload().gclid,'first');
});
test('retains Microsoft and Google iOS identifiers with their original casing',()=>{
 const b=browser(),d=document();b.location=new URL('https://site.test/?msclkid=AbC&gbraid=Def&wbraid=Xyz&utm_campaign=Casa');
 const p=new LeadAttribution(b,d).payload();assert.equal(p.msclkid,'AbC');assert.equal(p.gbraid,'Def');assert.equal(p.wbraid,'Xyz');assert.equal(p.utm_campaign,'Casa');
});
