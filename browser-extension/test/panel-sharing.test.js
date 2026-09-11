import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../src/panel.js', import.meta.url),'utf8');
const flow = source.slice(source.indexOf('async function shareSelectedProperties('), source.indexOf('\nfunction renderShareHistory'));
function setup({confirm=true, failSecond=false, pending=false, photoAccess=true}={}) {
  const calls=[];
  const node=()=>({textContent:'',disabled:false,classList:{add(){},remove(){},toggle(){}},setAttribute(){},removeAttribute(){}});
  const inputs=['7','8'].map(value=>{
    const input={...node(),value,checked:true}; const card={...node(),dataset:{sharePhotoUrl:`https://cdn.example.com/${value}`}}; let status=null;
    const body={append(n){status=n; n.remove=()=>{status=null;};}};
    card.querySelector=selector=>selector==='.pc-title'?{textContent:`Imóvel ${value}`}:selector==='.pc-card-body'?body:status;
    input.closest=()=>card;return input;
  });
  const button=node();const container={querySelectorAll:()=>inputs};
  const elements={'property-options':container,properties:container,'property-selection-actions':{querySelector:()=>button},'share-properties':button,feedback:node()};
  const selection=new Map(inputs.map(input=>[input.value,{}]));
  const pendingLinks=new Set(pending?['7','8']:[]);
  const context={console,document:{createElement:node},$:id=>elements[id],selectedLead:{id:1,name:'Cliente'},ready:()=>true,saving:false,
    context:{name:'Cliente',tabId:1},resolvedPhone:'5511999999999',contextKey:()=> 'chat',propertyLinkKey:id=>id,
    propertySelection:selection,pendingPropertyLinks:pendingLinks,revision:1,
    requestPropertyPhotoAccess:async()=>{if(!photoAccess)throw new Error('preview_permission_required');},
    crypto:{randomUUID:()=> 'progress'},chrome:{runtime:{id:'ext',onMessage:{addListener(){},removeListener(){}}}},
    window:{confirm:()=>confirm},syncShareSelection(){},syncPropertySelection(){},renderShareHistory(){},renderLeadProperties(){},
    request:async(type,payload)=>{
      calls.push({type,payload});
      if(type==='send_properties' && failSecond && payload.ids[0]==='8')throw new Error('send_unconfirmed');
      return type==='lead'?{properties:[]}:{sent:true,shares:{}};
    }};
  vm.createContext(context);vm.runInContext(flow,context);
  return {context,calls,inputs,selection,button};
}
test('denied photo access sends nothing and preserves selection in both share flows',async()=>{
  for(const fromSearch of [true,false]) {
    const state=setup({photoAccess:false});await state.context.shareSelectedProperties(fromSearch);
    assert.equal(state.calls.length,0);assert.equal(state.selection.size,2);
    assert.equal(state.button.disabled,false);
  }
});
test('canceling catalog confirmation performs no send or link',async()=>{
  const state=setup({confirm:false});await state.context.shareSelectedProperties(true);
  assert.equal(state.calls.length,0);assert.equal(state.selection.size,2);
});
test('catalog batch removes only confirmed sends and leaves the failed selection',async()=>{
  const state=setup({failSecond:true});await state.context.shareSelectedProperties(true);
  assert.equal(state.selection.has('7'),false);assert.equal(state.selection.has('8'),true);
  assert.equal(state.calls.filter(call=>call.type==='send_properties').length,2);
  assert.equal(state.calls.at(-1).type,'lead');assert.equal(state.button.disabled,false);
});
test('pending links use only the linking endpoint without a send confirmation',async()=>{
  const state=setup({confirm:false,pending:true});await state.context.shareSelectedProperties(true);
  assert.equal(state.calls.filter(call=>call.type==='link_properties').length,2);
  assert.equal(state.calls.some(call=>call.type==='send_properties'),false);
  assert.equal(state.selection.size,0);
});
