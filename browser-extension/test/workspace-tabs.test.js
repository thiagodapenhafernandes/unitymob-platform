import test from 'node:test';
import assert from 'node:assert/strict';
import { mountWorkspaceTabs, workspaceTabKey } from '../src/workspace-tabs.js';
function fixture() {
  const panels = Object.fromEntries(['lead','properties','tasks','history'].map(id => [`#pane-${id}`, {hidden:false,draft:'preserved'}]));
  const tabs = ['lead','properties','tasks','history'].map(id => ({
    dataset:{workspaceTab:id}, attrs:{'aria-controls':`pane-${id}`}, listeners:{},
    setAttribute(k,v){this.attrs[k]=v;}, getAttribute(k){return this.attrs[k];},
    addEventListener(k,fn){this.listeners[k]=fn;}, focus(){this.focused=true;}
  }));
  const listeners={};
  return {panels,tabs,root:{querySelectorAll:()=>tabs,querySelector:id=>panels[id],addEventListener:(key,fn)=>listeners[key]=fn,emit:visible=>listeners["workspace:lead-state"]({detail:visible})}};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
test('restores last tab when reopening; preserves drafts when switching',async()=>{
 const saved={}; const storage={get:async()=>saved,set:async v=>Object.assign(saved,v)};
 const a=fixture(); await mountWorkspaceTabs(a.root,storage); a.tabs[2].listeners.click(); await flush();
 const b=fixture(); await mountWorkspaceTabs(b.root,storage);
 assert.equal(saved[workspaceTabKey],'tasks'); assert.equal(b.panels['#pane-tasks'].hidden,false);
 assert.equal(b.panels['#pane-properties'].hidden,true); assert.equal(b.tabs[2].tabIndex,0);
 assert.equal(b.tabs[2].attrs['aria-selected'],'true'); assert.equal(a.panels['#pane-properties'].draft,'preserved');
});
test('late storage read does not override a new selection',async()=>{
 let restore; const f=fixture(); const loaded=mountWorkspaceTabs(f.root,{get:()=>new Promise(r=>restore=r),set:async()=>{}});
 f.tabs[3].listeners.click(); restore({[workspaceTabKey]:'tasks'}); await loaded;
 assert.equal(f.panels['#pane-history'].hidden,false);
});
test('invalid saved tab and storage failure leave navigation usable',async()=>{
 const f=fixture(); await mountWorkspaceTabs(f.root,{get:async()=>({[workspaceTabKey]:'unknown'}),set:async()=>{throw Error('unavailable');}});
 assert.equal(f.panels['#pane-lead'].hidden,false); f.tabs[2].listeners.click(); await flush();
 assert.equal(f.panels['#pane-tasks'].hidden,false);
 const g=fixture(); await mountWorkspaceTabs(g.root,{get:async()=>{throw Error('unavailable');}});
 assert.equal(g.panels['#pane-lead'].hidden,false);
});
test('keyboard wraps, handles Home/End, and saves final choice',async()=>{
 const f=fixture(),saved={}; await mountWorkspaceTabs(f.root,{get:async()=>saved,set:async v=>Object.assign(saved,v)});
 const key=(i,key)=>f.tabs[i].listeners.keydown({key,preventDefault(){}});
 key(0,'ArrowLeft'); assert.equal(f.tabs[3].focused,true);
 key(2,'Home'); assert.equal(f.panels['#pane-lead'].hidden,false);
 key(0,'ArrowRight'); assert.equal(f.panels['#pane-properties'].hidden,false);
 key(1,'End'); await flush(); assert.equal(saved[workspaceTabKey],'history');
});

test('missing lead opens Lead temporarily without losing the saved tab',async()=>{
 const f=fixture(),saved={[workspaceTabKey]:'tasks'};
 await mountWorkspaceTabs(f.root,{get:async()=>saved,set:async v=>Object.assign(saved,v)});
 f.root.emit(false); assert.equal(f.panels['#pane-lead'].hidden,false);
 assert.equal(f.tabs[2].disabled,true); assert.equal(saved[workspaceTabKey],'tasks');
 f.root.emit(true); assert.equal(f.panels['#pane-tasks'].hidden,false);
});
