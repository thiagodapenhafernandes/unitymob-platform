import {filterMarkup,enhanceFilters,restoreFilters,readFilters,mountSort} from './shared/catalog_controls.js';

export function mountPropertyCatalog({search,clearSelection}) {
  const pane=document.getElementById('pane-properties');
  const interests=document.getElementById('properties-section');
  const root=document.createElement('section');root.className='ax-property-catalog';root.setAttribute('aria-label','Carteira de imóveis');
  root.innerHTML=`<div data-list><div class="pc-toolbar"><label class="pc-search"><i class="bi bi-search" aria-hidden="true"></i><input type="search" aria-label="Buscar na carteira" placeholder="Código, imóvel, bairro…" maxlength="100"></label><button type="button" data-sort aria-label="Ordenar imóveis"><i class="bi bi-sort-down" aria-hidden="true"></i></button><button type="button" data-filter aria-label="Abrir filtros de imóveis"><i class="bi bi-funnel" aria-hidden="true"></i><span data-filter-count></span></button></div><div class="pc-facets" role="group" aria-label="Segmentos da carteira"></div><div class="pc-totals"><span data-total></span><strong data-filtered role="status"></strong></div><div data-results></div><button type="button" class="ax-btn" data-more hidden>Carregar mais imóveis</button></div><form data-filters hidden></form>`;
  pane.prepend(root);
  const $=s=>root.querySelector(s), form=$('[data-filters]');
  document.getElementById('property-search-form').hidden=true;
  for(const id of ['property-search-feedback','property-form'])$('[data-results]').append(document.getElementById(id));
  let filters={},facet='all',order='activity',direction='desc',page=1,active=false,loaded=false,hasOptions=false,timer,query='',busy=false;
  function run(reset=true){if(!active)return;if(reset){page=1;clearSelection();}search();}
  function close(){interests.hidden=false;form.hidden=true;$('[data-list]').hidden=false;$('[data-filter]').focus();}
  function configure(options={}){
    const draft = form.childElementCount && !form.hidden ? readFilters(form) : null;
    for(const el of form.querySelectorAll('select'))el.tomselect?.destroy();
    form.innerHTML=filterMarkup([],options);enhanceFilters(form);
    if(draft)restoreFilters(form,draft);
    form.querySelector('[data-back]').onclick=close;
    form.querySelector('[data-clear]').onclick=()=>restoreFilters(form);
  }
  configure();
  for(const [key,label,icon] of [['mine','Meus','house'],['venda','Venda','tag'],['locacao','Locação','key'],['opportunity','Oportunidades','star'],['all','Todos','archive']]){
    const b=document.createElement('button');b.type='button';b.dataset.facet=key;b.setAttribute('aria-pressed',String(key===facet));
    b.innerHTML=`<i class="bi bi-${icon}" aria-hidden="true"></i><span>${label}</span><strong>—</strong>`;
    b.onclick=()=>{facet=key;for(const item of $('.pc-facets').children)item.setAttribute('aria-pressed',String(item===b));run();};$('.pc-facets').append(b);
  }
  mountSort(root,(key,dir)=>{order=key;direction=dir;run();});
  $('.pc-search input').oninput=e=>{query=e.target.value;clearTimeout(timer);timer=setTimeout(()=>run(),300);};
  $('[data-filter]').onclick=()=>{restoreFilters(form,{...filters,query});$('[data-list]').hidden=true;interests.hidden=true;form.hidden=false;form.querySelector('[data-back]').focus();};
  form.onkeydown=e=>{if(e.key==='Escape'){e.preventDefault();close();}};
  form.onsubmit=e=>{e.preventDefault();const draft=readFilters(form);query=draft.query||'';delete draft.query;filters=draft;$('.pc-search input').value=query;$('[data-filter-count]').textContent=Object.values(filters).filter(Boolean).length||'';close();run();};
  $('[data-more]').onclick=()=>{if(busy)return;page++;run(false);};
  document.getElementById('add-properties').addEventListener('click',()=>{root.scrollIntoView({block:'start'});$('.pc-search input').focus();if(!loaded)run();});
  const observer=new MutationObserver(()=>{if(active&&!pane.hidden&&!loaded)run();});observer.observe(pane,{attributes:true,attributeFilter:['hidden']});
  return {
    criteria:()=>({catalog:true,purpose:'all',facet,order,direction,page,query:query.trim(),filters,includeOptions:!hasOptions}),
    activate(){active=true;loaded=false;page=1;if(!pane.hidden)run();},
    reset(){interests.hidden=false;active=false;loaded=false;hasOptions=false;busy=false;clearTimeout(timer);filters={};query='';page=1;form.hidden=true;$('[data-list]').hidden=false;$('.pc-search input').value='';$('[data-filter-count]').textContent='';$('[data-total]').textContent='';$('[data-filtered]').textContent='';$('[data-more]').hidden=true;configure();},
    loading(){busy=true;loaded=true;$('[data-more]').disabled=true;},
    failed(){busy=false;loaded=false;$('[data-more]').disabled=false;if(page>1)page--;},
    update(result){busy=false;loaded=true;$('[data-more]').disabled=false;$('[data-more]').hidden=!result.more;$('[data-total]').textContent=result.counts?`${result.counts.all} total`:'';$('[data-filtered]').textContent=result.total!=null?`${result.total} filtrados`:'';
      for(const b of $('.pc-facets').children)b.querySelector('strong').textContent=result.counts?.[b.dataset.facet]??'—';
      if(result.filter_options){configure(result.filter_options);hasOptions=true;}
    }
  };
}
