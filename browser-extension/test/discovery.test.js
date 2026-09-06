import test, { beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, copyFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const dir = await mkdtemp(join(tmpdir(), "unitymob-discovery-test-"));
for (const file of ["background.js", "context.js", "security.js", "launcher.js"]) await copyFile(new URL(`../src/${file}`, import.meta.url), join(dir, file));
await writeFile(join(dir, "package.json"), '{"type":"module"}');
await writeFile(join(dir, "config.js"), 'export const crmOrigins=["https://dev.unitymob.com.br"]; export const crmOrigin=crmOrigins[0]; export const discoveryOrigin="https://gateway.example.com";');
let listener, local, session, calls, issuer;
const account = {id: 1, tenant_id: "72", instance_id: "conexao", name: "Conexão", origin: "https://conexaobc.com"};
const store = get => ({async setAccessLevel(){}, async get(key){return {[key]:get()[key]};}, async set(value){Object.assign(get(), value);}, async remove(keys){for(const key of [keys].flat()) delete get()[key];}});
global.chrome = {
 runtime:{id:"a".repeat(32),getURL:path=>`chrome-extension://${"a".repeat(32)}/${path}`,onInstalled:{addListener(){}},onStartup:{addListener(){}},onMessage:{addListener(fn){listener=fn;}}},
 storage:{local:store(()=>local),session:store(()=>session)},
 tabs:{onUpdated:{addListener(){}}},action:{onClicked:{addListener(){}}},permissions:{async contains(){return true;}},
 identity:{getRedirectURL:()=>`https://${"a".repeat(32)}.chromiumapp.org/unitymob`,async launchWebAuthFlow({url}){
   calls.push({url}); const state=new URL(url).searchParams.get("challenge");
   return `${chrome.identity.getRedirectURL()}?state=${state}&login_token=signed&issuer=${encodeURIComponent(issuer)}`;
 }}
};
await import(pathToFileURL(join(dir,"background.js")));
const send = message => new Promise(resolve=>listener(message,{id:chrome.runtime.id,url:chrome.runtime.getURL("panel.html")},resolve));
const json = (data,status=200)=>new Response(JSON.stringify(data),{status,headers:{"Content-Type":"application/json"}});
beforeEach(()=>{
 local={};session={};calls=[];issuer=account.origin;
 global.fetch=async(url,options)=>{calls.push({url,options});
  if(url.endsWith("challenges")) return json({challenge:"c".repeat(43)},202);
  if(url.endsWith("verify")) return json({email:"broker@example.com",accounts:[account]});
  return json({tenant_id:"72",instance_id:"conexao",login_email:"broker@example.com",token:"t".repeat(43),expires_at:new Date(Date.now()+60000).toISOString()});
 };
});
after(()=>rm(dir,{recursive:true,force:true}));
async function verify(){assert.equal((await send({type:"discovery_start",email:"broker@example.com"})).ok,true);return send({type:"discovery_verify",code:"123456"});}
test("connects only a verified selected account and binds exchange to instance, tenant, email and issuer",async()=>{
 assert.equal((await verify()).ok,true);
 assert.equal((await send({type:"connect",accountId:1,origin:"https://evil.example.com"})).ok,true);
 assert.equal(local.connection.origin,account.origin);
 const exchange=calls.find(c=>c.options && c.url===`${account.origin}/api/v1/browser_extension/session`);
 assert.deepEqual(Object.fromEntries(Object.entries(JSON.parse(exchange.options.body)).filter(([key])=>key.startsWith("expected_")||key==="issuer")),{expected_tenant_id:"72",expected_email:"broker@example.com",expected_instance_id:"conexao",issuer:account.origin});
 assert.equal(session.discovery,undefined);
});
test("never accepts an arbitrary account or an expired discovery result",async()=>{
 await verify();
 assert.equal((await send({type:"connect",accountId:999})).ok,false);
 session.discovery.until=Date.now()-1;
 assert.equal((await send({type:"connect",accountId:1})).ok,false);
 assert.equal(calls.filter(c=>c.url.includes("conexaobc.com")).length,0);
});
test("rejects a callback issued by a different CRM before exchanging the code",async()=>{
 await verify();issuer="https://saluteimoveis.com.br";
 assert.equal((await send({type:"connect",accountId:1})).error,"account_mismatch");
 assert.equal(local.connection,undefined);
 assert.equal(calls.filter(c=>c.options && c.url.includes("conexaobc.com")).length,0);
});
test("does not return the challenge or CRM credential to the panel",async()=>{
 const started=await send({type:"discovery_start",email:"broker@example.com"});
 assert.deepEqual(started,{ok:true,data:{state:"code_sent"}});
 assert.equal(local.discovery,undefined);
});

test("rejects a legacy CRM that cannot attest the selected account",async()=>{
 await verify();
 global.fetch=async()=>json({token:"t".repeat(43),expires_at:new Date(Date.now()+60000).toISOString()});
 assert.equal((await send({type:"connect",accountId:1})).error,"account_mismatch");
 assert.equal(local.connection,undefined);
});
