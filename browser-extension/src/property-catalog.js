import {filterMarkup,enhanceFilters,restoreFilters,readFilters,mountSort} from './shared/catalog_controls.js';

export function mountPropertyCatalog({search,clearSelection,storage,scope}) {
  const pane=document.getElementById('pane-properties');
  const interests=document.getElementById('properties-section');
  const root=document.createElement('section');root.className='ax-property-catalog';root.setAttribute('aria-label','Carteira de imóveis');
  root.innerHTML=`<div data-list><div class="pc-toolbar"><label class="pc-search"><i class="bi bi-search" aria-hidden="true"></i><input type="search" aria-label="Buscar na carteira" placeholder="Código, imóvel, bairro…" maxlength="100"></label><button type="button" data-sort aria-label="Ordenar imóveis"><i class="bi bi-sort-down" aria-hidden="true"></i></button><button type="button" data-filter aria-label="Abrir filtros de imóveis"><i class="bi bi-funnel" aria-hidden="true"></i><span data-filter-count></span></button></div><div class="pc-totals"><span data-total></span><strong data-filtered role="status"></strong></div><div data-results></div><button type="button" class="ax-btn" data-more hidden>Tentar carregar novamente</button><div data-scroll-end aria-hidden="true" style="height:1px"></div></div><form data-filters hidden></form>`;
  const subnav=document.createElement('div');subnav.className='ax-workspace-tabs ax-workspace-tabs--compact pc-subtabs';subnav.setAttribute('role','tablist');subnav.setAttribute('aria-label','Listagens de imóveis');
  subnav.innerHTML='<button id="catalog-search-tab" type="button" role="tab" aria-controls="catalog-search-pane" aria-selected="true">Buscar imóveis</button><button id="catalog-interests-tab" type="button" role="tab" aria-controls="properties-section" aria-selected="false" tabindex="-1">Imóveis de interesse</button>';
  root.id='catalog-search-pane';root.setAttribute('role','tabpanel');root.setAttribute('aria-labelledby','catalog-search-tab');
  interests.setAttribute('role','tabpanel');interests.setAttribute('aria-labelledby','catalog-interests-tab');interests.hidden=true;
  pane.prepend(subnav,root);
  let view='search';
  function selectView(next){
    view=next;root.hidden=view!=='search';interests.hidden=view!=='interests';
    [...subnav.children].forEach((tab,index)=>{const selected=index===(view==='search'?0:1);tab.setAttribute('aria-selected',String(selected));tab.tabIndex=selected?0:-1;});
  }
  [...subnav.children].forEach((tab,index)=>{
    tab.onclick=()=>selectView(index===0?'search':'interests');
    tab.onkeydown=event=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;event.preventDefault();const target=event.key==='Home'?0:event.key==='End'?1:1-index;selectView(target===0?'search':'interests');subnav.children[target].focus();};
  });
  const tabs=document.querySelector('#workspace-panel [role="tablist"]');
  const tabsSize=new ResizeObserver(()=>{pane.style.setProperty('--pc-tabs-top',`${tabs.getBoundingClientRect().height}px`);root.style.setProperty('--pc-sticky-top',`${tabs.getBoundingClientRect().height+subnav.getBoundingClientRect().height}px`);});
  tabsSize.observe(tabs);tabsSize.observe(subnav);
  const $=s=>root.querySelector(s), form=$('[data-filters]');
  document.getElementById('property-search-form').hidden=true;
  for(const id of ['property-search-feedback','property-form'])$('[data-results]').append(document.getElementById(id));
  let filters={},order='activity',direction='desc',page=1,active=false,loaded=false,hasOptions=false,timer,query='',busy=false;
  let restoreVersion=0, storageKey=null;
  async function persist(){
    if(!storageKey)return;
    try { await storage.set({[storageKey]:JSON.stringify({filters,query,order,direction})}); } catch {}
  }
  function run(reset=true){if(!active)return;if(reset){page=1;clearSelection();}persist();search();}
  function close(){interests.hidden=view!=='interests';form.hidden=true;$('[data-list]').hidden=false;$('[data-filter]').focus();}
  function configure(options={}){
    const draft = form.childElementCount && !form.hidden ? readFilters(form) : null;
    for(const el of form.querySelectorAll('select'))el.tomselect?.destroy();
    form.innerHTML=filterMarkup([],options);enhanceFilters(form);
    if(draft)restoreFilters(form,draft);
    form.querySelector('[data-back]').onclick=close;
    form.querySelector('[data-clear]').onclick=()=>restoreFilters(form);
  }
  configure();
  const sorting=mountSort(root,(key,dir)=>{order=key;direction=dir;run();});
  $('.pc-search input').oninput=e=>{query=e.target.value;clearTimeout(timer);timer=setTimeout(()=>run(),300);};
  $('[data-filter]').onclick=()=>{restoreFilters(form,{...filters,query});$('[data-list]').hidden=true;interests.hidden=true;form.hidden=false;form.querySelector('[data-back]').focus();};
  form.onkeydown=e=>{if(e.key==='Escape'){e.preventDefault();close();}};
  form.onsubmit=e=>{e.preventDefault();const draft=readFilters(form);query=draft.query||'';delete draft.query;filters=draft;$('.pc-search input').value=query;$('[data-filter-count]').textContent=Object.values(filters).filter(Boolean).length||'';close();run();};
  let hasMore=false;
  function nextPage(){if(busy||!hasMore||!active||pane.hidden||root.hidden||!form.hidden)return;page++;run(false);}
  $('[data-more]').onclick=()=>{hasMore=true;$('[data-more]').hidden=true;nextPage();};
  const infiniteScroll=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting))nextPage();},{rootMargin:'0px 0px 120px 0px'});
  infiniteScroll.observe($('[data-scroll-end]'));
  const observer=new MutationObserver(()=>{if(active&&!pane.hidden&&!loaded)run();});observer.observe(pane,{attributes:true,attributeFilter:['hidden']});
  return {
    criteria:()=>({catalog:true,purpose:'all',facet:'all',order,direction,page,query:query.trim(),filters,includeOptions:!hasOptions}),
    async activate(){
      const version=++restoreVersion;
      active=false;
      storageKey=`catalogSearch:v1:${scope()}`;
      try {
        const saved=JSON.parse((await storage.get(storageKey))[storageKey] || 'null');
        if(version!==restoreVersion)return;
        if(saved && typeof saved==='object') {
          filters=saved.filters && typeof saved.filters==='object' && !Array.isArray(saved.filters)?saved.filters:{};
          query=typeof saved.query==='string'?saved.query.slice(0,100):'';
          order=saved.order || 'activity'; direction=saved.direction==='asc'?'asc':'desc';
          sorting.restore(order,direction);
        }
      } catch {}
      if(version!==restoreVersion)return;
      $('.pc-search input').value=query;
      $('[data-filter-count]').textContent=Object.values(filters).filter(Boolean).length||'';
      active=true;loaded=false;page=1;if(!pane.hidden)run();
    },
    reset(){hasMore=false;restoreVersion++;storageKey=null;order="activity";direction="desc";sorting.restore(order,direction);selectView('search');active=false;loaded=false;hasOptions=false;busy=false;clearTimeout(timer);filters={};query='';page=1;form.hidden=true;$('[data-list]').hidden=false;$('.pc-search input').value='';$('[data-filter-count]').textContent='';$('[data-total]').textContent='';$('[data-filtered]').textContent='';$('[data-more]').hidden=true;configure();},
    loading(){busy=true;loaded=true;$('[data-more]').disabled=true;},
    failed(){busy=false;loaded=true;hasMore=false;$('[data-more]').disabled=false;$('[data-more]').hidden=false;if(page>1)page--;else page=0;},
    update(result){busy=false;loaded=true;$('[data-more]').disabled=false;$('[data-more]').hidden=true;hasMore=result.more;$('[data-total]').textContent=result.counts?`${result.counts.all} total`:'';$('[data-filtered]').textContent=result.total!=null?`${result.total} filtrados`:'';
      if(result.filter_options){configure(result.filter_options);hasOptions=true;}
      requestAnimationFrame(()=>{infiniteScroll.unobserve($('[data-scroll-end]'));infiniteScroll.observe($('[data-scroll-end]'));});
    }
  };
}
