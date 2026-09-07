import {catalog} from './catalog.js';
import {filterWorkspace} from './property-workspace.js';
// Local demonstration adapter. The actual panel module remains unchanged.
const linked = new Set(['1842']);
const lead = {id:1842,name:'Mariana Souza',status:'Em Atendimento',owner_name:'Thiago',stage_id:1};
const me = {origin:location.origin,user:{id:1,name:'Thiago · demonstração'},tenant:{id:1,name:'Imobiliária demonstrativa'},
  capabilities:{read_leads:true,link_properties:true},terms:{text:''}};
const wait = ms => new Promise(resolve=>setTimeout(resolve,ms));
const adapter = async message => {
  switch(message.type) {
    case 'pair': return {state:'ready'};
    case 'me': return me;
    case 'snapshot': return {state:'ready',tabId:1,account:'demo',chatId:'demo@c.us',phone:'+5511999990000',name:lead.name};
    case 'resolve': return {leads:[lead],contact_phone:'+5511999990000'};
    case 'lead': return {lead,properties:catalog.filter(p=>linked.has(p.id)),tasks:[],notes:[],appointments:[],labels:[],label_catalog:[],
      property_categories:['Apartamento','Casa','Comercial'],property_quick_filters:{mobiliado:'Mobiliado',frente_mar:'Frente mar',piscina:'Piscina',sacada:'Sacada'}};
    case 'search_properties':
      await wait(350);
      {
        const stock=catalog.map((p,i)=>({...p,mine:i%3===0,opportunity:i===1,owner:'Thiago',activity:100-i,photo_urls:[]}));
        const results=filterWorkspace(stock,message).map(p=>({...p,linked:linked.has(p.id)}));
        const counts=Object.fromEntries(['all','mine','venda','locacao','opportunity'].map(facet=>[facet,filterWorkspace(stock,{facet}).length]));
        return {properties:results.slice((message.page-1)*20,message.page*20),total:results.length,counts,more:false,filter_options:message.includeOptions?{category:['Apartamento','Casa','Comercial'],development:catalog.map(p=>p.title),city:['Balneário Camboriú'],neighborhood:['Centro','Jardim','Barra Sul'],owner:['Thiago'],status:['Venda','Locação'],situation:['Novo','Usado'],keys:['Imobiliária','Proprietário']}:null};
      }
    case 'link_properties':
      for(const id of message.payload.ids.split(',')) if(catalog.some(p=>p.id===id)) linked.add(id);
      return {lead_id:lead.id};
    case 'unlink_property': linked.delete(String(message.payload.id)); return {lead_id:lead.id};
    case 'send_properties':
      alert('Simulação: nenhum imóvel foi enviado ao WhatsApp.'); return {};
    default: throw new Error('Ação indisponível nesta demonstração.');
  }
};
// No real Chrome APIs, credentials, network requests or CRM mutations.
globalThis.chrome = {
  runtime:{getManifest:()=>({version:'prévia'}),sendMessage:async message=>{
    try{return {ok:true,data:await adapter(message)};}catch{return {ok:false,error:'unavailable'};}
  }},
  storage:{local:{get:async key=>({[key]:localStorage.getItem(key)}),set:async values=>Object.entries(values).forEach(([k,v])=>localStorage.setItem(k,v))}},
  tabs:{query:async()=>[{id:1,url:'https://web.whatsapp.com/'}],onActivated:{addListener(){}},onUpdated:{addListener(){}}},
  permissions:{request:async()=>false}
};
document.addEventListener('click',event=>{
  if(event.target.closest('a[target="_blank"]')){event.preventDefault();alert('Link externo indisponível na demonstração.');}
});
await import('./panel.js');
