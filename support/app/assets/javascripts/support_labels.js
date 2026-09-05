(() => {
  if(window.supportLabelsBound)return;window.supportLabelsBound=true;
  function render(root,data){
    const list=root.querySelector('[data-label-list]');list.replaceChildren();
    data.labels.forEach(label=>{
      const row=document.createElement('div');row.className='ax-label-row';
      const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=label.applied;checkbox.disabled=data.resolved;checkbox.setAttribute('aria-label',`Aplicar ${label.name}`);
      checkbox.addEventListener('change',()=>mutate(root,`/${label.id}/apply`,'POST',{applied:checkbox.checked},()=>checkbox.checked=!checkbox.checked));
      const pill=document.createElement('span');pill.className='ax-support-status';pill.style.background=label.color;pill.style.color=label.text_color;pill.textContent=label.name;
      const desc=document.createElement('span');desc.className='ax-label-description';desc.textContent=label.description||'';
      const edit=document.createElement('button');edit.className='ax-btn';edit.textContent='Editar';edit.type='button';edit.addEventListener('click',()=>{
        const form=root.querySelector('[data-label-create]').cloneNode(true);form.removeAttribute('data-label-create');form.elements.name.value=label.name;form.elements.color.value=label.color;form.elements.description.value=label.description||'';form.querySelector('button').textContent='Salvar';
        const cancel=document.createElement('button');cancel.type='button';cancel.className='ax-btn';cancel.textContent='Cancelar';cancel.onclick=()=>render(root,data);form.append(cancel);
        form.onsubmit=event=>{event.preventDefault();mutate(root,`/${label.id}`,'PATCH',{label:Object.fromEntries(new FormData(form))});};row.replaceChildren(form);
      });
      const remove=document.createElement('button');remove.type='button';remove.className='ax-btn';remove.textContent='Excluir';remove.onclick=()=>{if(confirm(`Excluir “${label.name}” do catálogo e de todos os chamados?`))mutate(root,`/${label.id}`,'DELETE');};
      row.append(checkbox,pill,desc,edit,remove);list.append(row);
    });
    if(!data.labels.length)list.textContent='Nenhuma etiqueta no catálogo. Crie a primeira acima.';
    const panel=root.closest('[data-support-tabs]');const count=data.labels.filter(x=>x.applied).length;
    const card=document.querySelector(`[data-support-ticket-link="${root.dataset.labelTicket}"]`)?.closest('.ax-support-ticket-card');
    if(card){card.querySelector('.ax-label-badges')?.remove();const badges=document.createElement('div');badges.className='ax-label-badges';data.labels.filter(x=>x.applied).forEach(label=>{const pill=document.createElement('span');pill.className='ax-support-status';pill.textContent=label.name;pill.style.background=label.color;pill.style.color=label.text_color;badges.append(pill);});if(count)card.insertBefore(badges,card.querySelector('.ax-support-assignee'));}
    if(panel)panel.querySelector('[data-support-tab=labels]').textContent=`Etiquetas (${count})`;
  }
  async function mutate(root,suffix='',method='GET',body,rollback){
    if(root.dataset.loading){rollback?.();return;}root.dataset.loading='true';const error=root.querySelector('[data-label-error]');error.hidden=true;
    try{
      const url=new URL(root.dataset.labelCatalog,location.href);url.pathname+=suffix;
      const response=await fetch(url,{method,headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:body?JSON.stringify(body):undefined});
      const data=await response.json();if(!response.ok)throw new Error(data.error||'Não foi possível salvar as etiquetas.');
      if(root.isConnected){render(root,data);if(method!=='GET'){root.querySelector('[data-label-create]').reset();root.querySelector('details').open=false;root.querySelectorAll('form').forEach(form=>delete form.dataset.dirty);}}
    }catch(e){rollback?.();error.textContent=e.message;error.hidden=false;}finally{delete root.dataset.loading;}
  }
  function setup(){document.querySelectorAll('[data-label-catalog]').forEach(root=>{if(root.dataset.bound)return;root.dataset.bound='true';root.querySelector('[data-label-create]').onsubmit=event=>{event.preventDefault();mutate(root,'','POST',{label:Object.fromEntries(new FormData(event.target))});};mutate(root);});}
  document.addEventListener('turbo:load',setup);document.addEventListener('turbo:frame-load',setup);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',setup);else setup();
})();
