(()=>{
 const buttons=[...document.querySelectorAll('[data-extension-step]')],scenes=[...document.querySelectorAll('.extension-scene')],play=document.getElementById('extension-play');
 if(!buttons.length)return;
 const descriptions=['Busque por código, empreendimento ou localização. Compare características e valores e abra as fotos sem sair do atendimento.','Escolha os imóveis, confira o destinatário e confirme o envio. Os links são compartilhados com o contato da conversa atual.','Registre tipo, resultado e resumo do contato. Crie tarefas e compromissos para organizar a continuidade do atendimento.'];
 const labels=['Busca de imóveis','Envio com confirmação','Histórico e próximos passos'];let sequence,active=0;const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 const stop=()=>{sequence?.kill();sequence=null;play.textContent='Reproduzir sequência';};
 function select(index,animate=false){active=index;buttons.forEach((b,i)=>b.setAttribute('aria-pressed',String(index===i)));scenes.forEach((s,i)=>s.style.display=i===index?'':'none');document.getElementById('extension-explanation').textContent=descriptions[index];document.getElementById('extension-step-label').textContent=`0${index+1} / ${labels[index]}`;if(window.gsap&&animate&&!reduced.matches)gsap.fromTo(scenes[index],{opacity:.25,y:6},{opacity:1,y:0,duration:.3,ease:'power2.out',overwrite:true});}
 buttons.forEach((b,i)=>b.onclick=()=>{stop();select(i,true);});
 play.onclick=()=>{if(sequence){stop();return;}play.textContent='Pausar sequência';sequence=gsap.timeline({onComplete:()=>{sequence=null;play.textContent='Reproduzir novamente';}});for(let i=0;i<3;i++)sequence.call(()=>select(i,true),[],i*3.5);sequence.to({},{duration:3.5});};
 function adapt(){stop();play.hidden=reduced.matches||!window.gsap;select(active);}reduced.addEventListener('change',adapt);document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});adapt();
})();
