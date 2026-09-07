import TomSelect from '../vendor/tom-select.js';
export const sortOptions=[
 ['activity','Última atividade','desc'],['code','Código mais recente','desc'],['category','Categoria','asc'],
 ['address','Endereço','asc'],['number','Endereço número','asc'],['complement','Endereço complemento','asc'],
 ['bedrooms','Dormitório','desc'],['sale_price','Valor venda','desc'],['rental_price','Valor aluguel','desc'],
 ['neighborhood','Bairro comercial','asc'],['title','Empreendimento','asc'],['rental_m2','Valor M2 aluguel','desc'],
 ['sale_m2','Valor M2 venda','desc'],['rental_total','Valor total aluguel','desc']
];
export const quickOptions=[['destaque_web','Destaque Web'],['oportunidade','Oportunidade'],['frente_mar','Frente Mar'],['lancamento','Lançamento'],['na_planta','Na Planta'],['mobiliado','Mobiliado'],['semi_mobiliado','Semi mobiliado'],['sem_mobilia','Sem mobília'],['diferenciado','Diferenciado'],['quadra_mar','Quadra mar'],['dependencia_empregada','Dependência'],['cozinha_gourmet_churrasqueira','Cozinha gourmet'],['sol_manha','Sol manhã'],['sol_tarde','Sol tarde'],['sol_dia_todo','Sol dia todo'],['decorado','Decorado']];
const escape=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const input=(name,label,{prefix='',placeholder='',type='text'}={})=>`<label>${label}<span class="pc-input-group">${prefix?`<span>${prefix}</span>`:''}<input name="${name}" type="${type}" ${type==='number'?'min="0" step="any"':''} placeholder="${placeholder}"></span></label>`;
const select=(name,label,options,multiple=false,placeholder='Todos')=>`<label>${label}<select name="${name}" data-enhance ${multiple?'multiple':''} placeholder="${placeholder}"><option value="">${placeholder}</option>${options.map(o=>{const [v,t]=Array.isArray(o)?o:[o,o];return `<option value="${escape(v)}">${escape(t)}</option>`;}).join('')}</select></label>`;
const checks=(name,options)=>`<div class="pc-checks">${options.map(([v,t])=>`<label><input type="checkbox" name="${name}" value="${v}">${t}</label>`).join('')}</div>`;
const group=(name,glyph,body,open=false)=>`<details class="pc-filter-group" ${open?'open':''}><summary><i class="bi bi-${glyph}" aria-hidden="true"></i>${name}<i class="bi bi-chevron-down" aria-hidden="true"></i></summary><div class="pc-group-body">${body}</div></details>`;
export function filterMarkup(items=[],options={}){
 const unique=key=>options[key] || [...new Set(items.map(p=>p[key]).filter(Boolean))];
 const yesNo=[['1','Sim'],['0','Não']];
 return `<header class="pc-filter-header"><h2>FILTROS DO CATÁLOGO</h2><button type="button" data-back aria-label="Fechar filtros"><i class="bi bi-x-lg" aria-hidden="true"></i></button></header><div class="pc-filter-scroll"><div class="pc-filter-actions"><button type="submit"><i class="bi bi-search" aria-hidden="true"></i> Aplicar filtros</button><button type="button" data-clear><i class="bi bi-eraser" aria-hidden="true"></i> Limpar</button></div>
 ${group('Filtros rápidos','stars',input('query','Palavra-chave',{placeholder:'Busque por código, imóvel, bairro…'})+checks('quick',quickOptions))}
 ${group('Dados','database',input('reference','Referência',{prefix:'#',placeholder:'Ex.: 1842'})+select('development','Empreendimento',(options.development || unique('title')),true,'Selecione empreendimento')+select('owner','Captador responsável',unique('owner'),true,'Selecione captador')+'<div class="pc-cut"><span>RECORTE</span><strong>Tipo de cadastro e status comercial</strong></div>'+select('status','Status comercial',(options.status || ['Venda','Locação']),true,'Todos')+select('category','Categoria',unique('category'),true,'Todas')+'<div class="pc-value-label">VALOR</div>'+input('min_price','Valor mínimo',{prefix:'R$',placeholder:'Mín.',type:'number'})+input('max_price','Valor máximo',{prefix:'R$',placeholder:'Máx.',type:'number'}),true)}
 ${group('Localização','geo-alt',select('city','Cidade',unique('city'),true,'Selecione cidade')+input('address','Logradouro')+input('number','Nº')+select('neighborhood','Bairro comercial',unique('neighborhood'),true,'Selecione bairro'))}
 ${group('Negociação','cash-coin',select('situation','Situação',unique('situation'),true,'Todas')+select('promotion','Preço reduzido',[['1','Com preço reduzido'],['0','Sem preço reduzido']])+select('exchange','Aceita permuta',yesNo)+select('installments','Parcelamento',yesNo)+select('keys','Chaves',(options.keys || ['Imobiliária','Proprietário']))+select('rental_management','Administração de locação',yesNo)+checks('exchange_type',[['vehicle','Aceita veículo'],['property','Aceita imóvel'],['others','Aceita outros']]))}
 ${group('Características do imóvel','sliders',[
 ['bedrooms','Dormitórios'],['suites','Suítes'],['bathrooms','Banheiros'],['parking','Vagas'],['area_total','Área total'],['area','Área privativa']
 ].map(([key,label])=>input(`${key}_min`,`${label} mín.`,{type:'number'})+input(`${key}_max`,`${label} máx.`,{type:'number'})).join('')+'<strong>CARACTERÍSTICAS INTERNAS</strong>'+checks('amenities',[['Mobiliado','Mobiliado'],['Sacada','Sacada'],['Churrasqueira','Churrasqueira']])+'<strong>CARACTERÍSTICAS DO EMPREENDIMENTO</strong>'+checks('amenities',[['Piscina','Piscina'],['Elevador','Elevador'],['Academia','Academia']]),true)}
 </div>`;
}
export function enhanceFilters(form){
 for(const el of form.querySelectorAll('[data-enhance]'))new TomSelect(el,{plugins:['remove_button','clear_button'],create:false,allowEmptyOption:false,closeAfterSelect:true});
}
export function restoreFilters(form,values={}){
 form.reset();
 for(const el of form.querySelectorAll('input,select')){
  const value=values[el.name]??'';
  el.setCustomValidity('');
  if(el.tomselect){el.tomselect.clear(true);el.tomselect.setValue(value,true);}
  else if(el.type==='checkbox')el.checked=(Array.isArray(value)?value:[value]).includes(el.value);
  else el.value=value;
 }
}
export function readFilters(form){
 const data=new FormData(form),result={};
 for(const key of new Set(data.keys())){
  const values=data.getAll(key).filter(Boolean);
  result[key]=values.length>1?values:values[0]||'';
 }
 return result;
}
export function mountSort(root,onSelect){
 const trigger=root.querySelector('[data-sort]');
 const menu=document.createElement('div');menu.className='pc-sort-menu';menu.hidden=true;menu.setAttribute('role','menu');menu.setAttribute('aria-label','Ordenar por');menu.id='catalog-sort-menu';
 trigger.setAttribute('aria-controls',menu.id);trigger.setAttribute('aria-haspopup','menu');
 root.querySelector('.pc-toolbar').append(menu);
 let current='activity',direction='desc';
 const close=focus=>{menu.hidden=true;trigger.setAttribute('aria-expanded','false');if(focus)trigger.focus();};
 function render(){menu.innerHTML=`<div class="pc-sort-heading"><strong>ORDENAR POR</strong><span>${direction}</span></div>`;
 for(const [key,label,defaultDirection] of sortOptions){const b=document.createElement('button');b.type='button';b.setAttribute('role','menuitemradio');b.setAttribute('aria-checked',String(key===current));b.innerHTML=`<span class="pc-sort-check">${key===current?'✓':''}</span><span>${label}</span><small>${key===current?'Atual':''}</small>`;
 b.onclick=()=>{direction=key===current?(direction==='asc'?'desc':'asc'):defaultDirection;current=key;onSelect(current,direction);close(true);};menu.append(b);}}
 trigger.onclick=()=>{if(!menu.hidden){close(false);return;}render();menu.hidden=false;trigger.setAttribute('aria-expanded','true');menu.querySelector('[aria-checked="true"]').focus();};
 document.addEventListener('click',e=>{if(!menu.contains(e.target)&&!trigger.contains(e.target))close(false);});
 menu.addEventListener('keydown',e=>{
 if(e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();close(true);return;}
 if(e.key==='Tab'){close(false);return;}
 const buttons=[...menu.querySelectorAll('button')],i=buttons.indexOf(document.activeElement);
 const next=e.key==='ArrowDown'?(i+1)%buttons.length:e.key==='ArrowUp'?(i+buttons.length-1)%buttons.length:e.key==='Home'?0:e.key==='End'?buttons.length-1:null;
 if(next!==null){e.preventDefault();buttons[next].focus();}
 },true);
 return {restore(key,dir){current=sortOptions.some(([value])=>value===key)?key:'activity';direction=dir==='asc'?'asc':'desc';close(false);}};
}
