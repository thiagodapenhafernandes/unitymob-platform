// Integração do motor do NotificaLead com os formulários e Turbo Frames da central.
(() => {
  if (window.supportImageEditorBound) return;
  window.supportImageEditorBound = true;
  const tools = [ ['crop','Recortar (C)','⌗'], ['blur','Borrar área (B)','◐'], ['text','Texto (T)','T'], ['draw','Lápis (D)','✎'], ['arrow','Seta (A)','↗'], ['rect','Retângulo (R)','□'], ['ellipse','Elipse (O)','○'], ['erase','Apagar anotação (E)','▱'], ['move','Mover (V)','✥'] ];
  const colors = ['#ff2d2d','#f59e0b','#eab308','#22c55e','#3b82f6','#a855f7','#ec4899','#ffffff','#111827'];
  const configs = {draw:['size',1,24,4,'Traço'],arrow:['size',2,20,4,'Traço'],rect:['size',1,16,4,'Borda'],ellipse:['size',1,16,4,'Borda'],text:['textFontSize',12,96,50,'Fonte'],blur:['blurRadius',4,30,12,'Blur']};
  const icons = {"crop": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-crop\" viewBox=\"0 0 16 16\">\n  <path d=\"M3.5.5A.5.5 0 0 1 4 1v13h13a.5.5 0 0 1 0 1h-2v2a.5.5 0 0 1-1 0v-2H3.5a.5.5 0 0 1-.5-.5V4H1a.5.5 0 0 1 0-1h2V1a.5.5 0 0 1 .5-.5zm2.5 3a.5.5 0 0 1 .5-.5h8a.5.5 0 0 1 .5.5v8a.5.5 0 0 1-1 0V4H6.5a.5.5 0 0 1-.5-.5z\"/>\n</svg>", "blur": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-droplet-half\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M7.21.8C7.69.295 8 0 8 0c.109.363.234.708.371 1.038.812 1.946 2.073 3.35 3.197 4.6C12.878 7.096 14 8.345 14 10a6 6 0 0 1-12 0C2 6.668 5.58 2.517 7.21.8zm.413 1.021A31.25 31.25 0 0 0 5.794 3.99c-.726.95-1.436 2.008-1.96 3.07C3.304 8.133 3 9.138 3 10c0 0 2.5 1.5 5 .5s5-.5 5-.5c0-1.201-.796-2.157-2.181-3.7l-.03-.032C9.75 5.11 8.5 3.72 7.623 1.82z\"/>\n  <path fill-rule=\"evenodd\" d=\"M4.553 7.776c.82-1.641 1.717-2.753 2.093-3.13l.708.708c-.29.29-1.128 1.311-1.907 2.87l-.894-.448z\"/>\n</svg>", "text": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-fonts\" viewBox=\"0 0 16 16\">\n  <path d=\"M12.258 3h-8.51l-.083 2.46h.479c.26-1.544.758-1.783 2.693-1.845l.424-.013v7.827c0 .663-.144.82-1.3.923v.52h4.082v-.52c-1.162-.103-1.306-.26-1.306-.923V3.602l.431.013c1.934.062 2.434.301 2.693 1.846h.479L12.258 3z\"/>\n</svg>", "draw": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-pencil-fill\" viewBox=\"0 0 16 16\">\n  <path d=\"M12.854.146a.5.5 0 0 0-.707 0L10.5 1.793 14.207 5.5l1.647-1.646a.5.5 0 0 0 0-.708l-3-3zm.646 6.061L9.793 2.5 3.293 9H3.5a.5.5 0 0 1 .5.5v.5h.5a.5.5 0 0 1 .5.5v.5h.5a.5.5 0 0 1 .5.5v.5h.5a.5.5 0 0 1 .5.5v.207l6.5-6.5zm-7.468 7.468A.5.5 0 0 1 6 13.5V13h-.5a.5.5 0 0 1-.5-.5V12h-.5a.5.5 0 0 1-.5-.5V11h-.5a.5.5 0 0 1-.5-.5V10h-.5a.499.499 0 0 1-.175-.032l-.179.178a.5.5 0 0 0-.11.168l-2 5a.5.5 0 0 0 .65.65l5-2a.5.5 0 0 0 .168-.11l.178-.178z\"/>\n</svg>", "arrow": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-arrow-up-right\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M14 2.5a.5.5 0 0 0-.5-.5h-6a.5.5 0 0 0 0 1h4.793L2.146 13.146a.5.5 0 0 0 .708.708L13 3.707V8.5a.5.5 0 0 0 1 0v-6z\"/>\n</svg>", "rect": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-square\" viewBox=\"0 0 16 16\">\n  <path d=\"M14 1a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1h12zM2 0a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V2a2 2 0 0 0-2-2H2z\"/>\n</svg>", "ellipse": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-circle\" viewBox=\"0 0 16 16\">\n  <path d=\"M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14zm0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16z\"/>\n</svg>", "erase": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-eraser-fill\" viewBox=\"0 0 16 16\">\n  <path d=\"M8.086 2.207a2 2 0 0 1 2.828 0l3.879 3.879a2 2 0 0 1 0 2.828l-5.5 5.5A2 2 0 0 1 7.879 15H5.12a2 2 0 0 1-1.414-.586l-2.5-2.5a2 2 0 0 1 0-2.828l6.879-6.879zm.66 11.34L3.453 8.254 1.914 9.793a1 1 0 0 0 0 1.414l2.5 2.5a1 1 0 0 0 .707.293H7.88a1 1 0 0 0 .707-.293l.16-.16z\"/>\n</svg>", "move": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-arrows-move\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M7.646.146a.5.5 0 0 1 .708 0l2 2a.5.5 0 0 1-.708.708L8.5 1.707V5.5a.5.5 0 0 1-1 0V1.707L6.354 2.854a.5.5 0 1 1-.708-.708l2-2zM8 10a.5.5 0 0 1 .5.5v3.793l1.146-1.147a.5.5 0 0 1 .708.708l-2 2a.5.5 0 0 1-.708 0l-2-2a.5.5 0 0 1 .708-.708L7.5 14.293V10.5A.5.5 0 0 1 8 10zM.146 8.354a.5.5 0 0 1 0-.708l2-2a.5.5 0 1 1 .708.708L1.707 7.5H5.5a.5.5 0 0 1 0 1H1.707l1.147 1.146a.5.5 0 0 1-.708.708l-2-2zM10 8a.5.5 0 0 1 .5-.5h3.793l-1.147-1.146a.5.5 0 0 1 .708-.708l2 2a.5.5 0 0 1 0 .708l-2 2a.5.5 0 0 1-.708-.708L14.293 8.5H10.5A.5.5 0 0 1 10 8z\"/>\n</svg>", "undo": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-arrow-counterclockwise\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M8 3a5 5 0 1 1-4.546 2.914.5.5 0 0 0-.908-.417A6 6 0 1 0 8 2v1z\"/>\n  <path d=\"M8 4.466V.534a.25.25 0 0 0-.41-.192L5.23 2.308a.25.25 0 0 0 0 .384l2.36 1.966A.25.25 0 0 0 8 4.466z\"/>\n</svg>", "redo": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-arrow-clockwise\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z\"/>\n  <path d=\"M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z\"/>\n</svg>", "clear": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-trash3\" viewBox=\"0 0 16 16\">\n  <path d=\"M6.5 1h3a.5.5 0 0 1 .5.5v1H6v-1a.5.5 0 0 1 .5-.5ZM11 2.5v-1A1.5 1.5 0 0 0 9.5 0h-3A1.5 1.5 0 0 0 5 1.5v1H2.506a.58.58 0 0 0-.01 0H1.5a.5.5 0 0 0 0 1h.538l.853 10.66A2 2 0 0 0 4.885 16h6.23a2 2 0 0 0 1.994-1.84l.853-10.66h.538a.5.5 0 0 0 0-1h-.995a.59.59 0 0 0-.01 0H11Zm1.958 1-.846 10.58a1 1 0 0 1-.997.92h-6.23a1 1 0 0 1-.997-.92L3.042 3.5h9.916Zm-7.487 1a.5.5 0 0 1 .528.47l.5 8.5a.5.5 0 0 1-.998.06L5 5.03a.5.5 0 0 1 .47-.53Zm5.058 0a.5.5 0 0 1 .47.53l-.5 8.5a.5.5 0 1 1-.998-.06l.5-8.5a.5.5 0 0 1 .528-.47ZM8 4.5a.5.5 0 0 1 .5.5v8.5a.5.5 0 0 1-1 0V5a.5.5 0 0 1 .5-.5Z\"/>\n</svg>", "zoomOut": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-zoom-out\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M6.5 12a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11zM13 6.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0z\"/>\n  <path d=\"M10.344 11.742c.03.04.062.078.098.115l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85a1.007 1.007 0 0 0-.115-.1 6.538 6.538 0 0 1-1.398 1.4z\"/>\n  <path fill-rule=\"evenodd\" d=\"M3 6.5a.5.5 0 0 1 .5-.5h6a.5.5 0 0 1 0 1h-6a.5.5 0 0 1-.5-.5z\"/>\n</svg>", "fitToScreen": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-aspect-ratio\" viewBox=\"0 0 16 16\">\n  <path d=\"M0 3.5A1.5 1.5 0 0 1 1.5 2h13A1.5 1.5 0 0 1 16 3.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 0 12.5v-9zM1.5 3a.5.5 0 0 0-.5.5v9a.5.5 0 0 0 .5.5h13a.5.5 0 0 0 .5-.5v-9a.5.5 0 0 0-.5-.5h-13z\"/>\n  <path d=\"M2 4.5a.5.5 0 0 1 .5-.5h3a.5.5 0 0 1 0 1H3v2.5a.5.5 0 0 1-1 0v-3zm12 7a.5.5 0 0 1-.5.5h-3a.5.5 0 0 1 0-1H13V8.5a.5.5 0 0 1 1 0v3z\"/>\n</svg>", "zoomIn": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-zoom-in\" viewBox=\"0 0 16 16\">\n  <path fill-rule=\"evenodd\" d=\"M6.5 12a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11zM13 6.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0z\"/>\n  <path d=\"M10.344 11.742c.03.04.062.078.098.115l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85a1.007 1.007 0 0 0-.115-.1 6.538 6.538 0 0 1-1.398 1.4z\"/>\n  <path fill-rule=\"evenodd\" d=\"M6.5 3a.5.5 0 0 1 .5.5V6h2.5a.5.5 0 0 1 0 1H7v2.5a.5.5 0 0 1-1 0V7H3.5a.5.5 0 0 1 0-1H6V3.5a.5.5 0 0 1 .5-.5z\"/>\n</svg>", "close": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-x-lg\" viewBox=\"0 0 16 16\">\n  <path d=\"M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707l-5.146 5.147a.5.5 0 0 1-.708-.708L7.293 8 2.146 2.854Z\"/>\n</svg>", "send": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-send-fill\" viewBox=\"0 0 16 16\">\n  <path d=\"M15.964.686a.5.5 0 0 0-.65-.65L.767 5.855H.766l-.452.18a.5.5 0 0 0-.082.887l.41.26.001.002 4.995 3.178 3.178 4.995.002.002.26.41a.5.5 0 0 0 .886-.083l6-15Zm-1.833 1.89L6.637 10.07l-.215-.338a.5.5 0 0 0-.154-.154l-.338-.215 7.494-7.494 1.178-.471-.47 1.178Z\"/>\n</svg>"};
  let active;
  class AttachmentEditor {
    constructor(input, file, img) {
      this.input=input; this.form=input.form; this.file=file; this.sizes={}; this.color=colors[0]; this.previousFocus=document.activeElement;
      this.dialog=document.createElement('dialog'); this.dialog.className='ax-image-editor';this.dialog.setAttribute('aria-label','Editar imagem anexada');
      this.dialog.innerHTML=`<div class="ax-image-editor__canvas"><canvas></canvas><textarea class="ax-image-editor__text" aria-label="Texto na imagem" placeholder="Digite…" rows="1" wrap="off" hidden></textarea></div>
        <div class="ax-image-editor__top"><button type="button" data-command="close" aria-label="Fechar editor" title="Fechar (Esc)">×</button><div class="ax-image-editor__tools">${tools.map(([tool,label,icon])=>`<button type="button" data-tool="${tool}" aria-label="${label}" title="${label}">${icon}</button>`).join('')}</div></div>
        <div class="ax-image-editor__context"><div data-size-panel><label for="ax-image-size" data-size-label>Traço</label><input id="ax-image-size" type="range" min="1" max="24" value="4"><i data-size-preview></i><output>4</output></div><div data-palette>${colors.map(color=>`<button type="button" data-color="${color}" style="background:${color}" aria-label="Cor ${color}"></button>`).join('')}<input type="color" aria-label="Cor personalizada" value="#ff2d2d"></div><label data-fill-label><input type="checkbox" data-fill> Preencher</label></div>
        <div class="ax-image-editor__secondary">${[['undo','Desfazer (Ctrl+Z)','↶'],['redo','Refazer (Ctrl+Y)','↷'],['clear','Limpar anotações','♜'],['zoomOut','Diminuir zoom','⊖'],['fitToScreen','Ajustar à tela','▣'],['zoomIn','Aumentar zoom','⊕']].map(([cmd,label,icon])=>`<button type="button" data-command="${cmd}" aria-label="${label}" title="${label}">${icon}</button>`).join('')}</div>
        <span class="ax-image-editor__filename"></span><div class="ax-image-editor__footer"><p role="alert" data-error hidden></p><div><textarea rows="1" data-caption aria-label="Mensagem da imagem" placeholder="Adicionar mensagem (opcional)"></textarea><button type="button" data-command="send" aria-label="Concluir e enviar" title="Concluir e enviar">➤</button></div></div>`;
      this.dialog.querySelectorAll('button[data-tool],button[data-command]').forEach(button=>{button.innerHTML=icons[button.dataset.tool||button.dataset.command];});
      document.body.append(this.dialog);this.dialog.showModal();document.body.classList.add('ax-image-editor-open');
      this.q('.ax-image-editor__filename').textContent=file.name;
      this.q('[data-caption]').value=this.form.querySelector('textarea[name=body]')?.value || '';
      this.engine=new window.SupportImageEditor({canvas:this.q('canvas'),onToolChange:tool=>this.syncTool(tool),onHistoryChange:({canUndo,canRedo})=>{this.q('[data-command=undo]').disabled=!canUndo;this.q('[data-command=redo]').disabled=!canRedo;},onRequestText:payload=>this.openText(payload)});
      this.engine.loadImage(img);this.engine.setColor(this.color);this.engine.setTool('draw');
      this.dialog.addEventListener('click',event=>this.click(event));
      this.dialog.addEventListener('input',event=>this.change(event));
      this.dialog.addEventListener('cancel',event=>{event.preventDefault();this.close();});
      this.dialog.addEventListener('keydown',event=>this.keydown(event));
      this.q('.ax-image-editor__text').addEventListener('blur',()=>this.commitText());
      this.onTextResize=()=>this.layoutText();window.addEventListener('resize',this.onTextResize);
      this.q('[data-caption]').focus();requestAnimationFrame(()=>this.engine?.fitToScreen());
    }
    q(selector){return this.dialog.querySelector(selector);}
    syncTool(tool){
      this.tool=tool; const cfg=configs[tool]; const colorful=!!cfg && tool!=='blur';
      this.dialog.querySelectorAll('[data-tool]').forEach(button=>{const selected=button.dataset.tool===tool;button.setAttribute('aria-pressed',selected);button.style.background=selected?(colorful?this.color:'#10b981'):'';button.style.color=selected&&['#ffffff','#eab308'].includes(this.color)&&colorful?'#111':'#fff';});
      this.q('[data-size-panel]').hidden=!cfg;this.q('[data-palette]').hidden=!colorful;this.q('[data-fill-label]').hidden=!['rect','ellipse'].includes(tool);
      if(cfg){const [property,min,max,initial,label]=cfg;const slider=this.q('[type=range]');slider.min=min;slider.max=max;slider.value=this.sizes[property]??initial;slider.style.accentColor=this.color;this.q('[data-size-label]').textContent=label;this.setSize();}
      this.dialog.querySelectorAll('[data-color]').forEach(button=>button.setAttribute('aria-pressed',button.dataset.color===this.color));
    }
    setSize(){const cfg=configs[this.tool];if(!cfg)return;const value=Number(this.q('[type=range]').value);this.sizes[cfg[0]]=value;this.engine['set'+cfg[0][0].toUpperCase()+cfg[0].slice(1)](value);this.q('output').textContent=value;const dot=this.q('[data-size-preview]');dot.style.width=dot.style.height=Math.min(24,Math.max(3,value*(cfg[0]==='textFontSize'?.25:1)))+'px';dot.style.background=this.color;if(this.textState){this.textState.fontSize=value;this.layoutText();}}
    change(event){if(event.target.matches('.ax-image-editor__text'))this.layoutText();if(event.target.matches('[type=range]'))this.setSize();if(event.target.matches('[type=color]'))this.setColor(event.target.value);if(event.target.matches('[data-fill]'))this.engine.setShapeFill(event.target.checked);}
    setColor(color){this.color=color;this.engine.setColor(color);this.q('[type=color]').value=color;this.syncTool(this.tool);if(this.textState){this.textState.color=color;this.q('.ax-image-editor__text').style.color=color;}}
    click(event){const button=event.target.closest('button');if(!button||this.sending)return;if(button.dataset.tool){this.commitText();this.engine.setTool(button.dataset.tool);}if(button.dataset.color)this.setColor(button.dataset.color);const command=button.dataset.command;if(command==='close')this.close();else if(command==='send')this.send();else if(command){this.commitText();this.engine[command]();}}
    openText(payload){
      this.commitText();this.textState=payload;
      const field=this.q('.ax-image-editor__text');field.hidden=false;field.value='';
      this.layoutText();requestAnimationFrame(()=>field.focus());
    }
    layoutText(){
      if(!this.textState)return;
      const field=this.q('.ax-image-editor__text'), state=this.textState;
      // Fonte em pixels da imagem; transforma também a caixa pela escala real do canvas.
      const point=this.engine.canvasToScreen(state.canvasX,state.canvasY);
      const family="'Inter', 'Helvetica Neue', Arial, sans-serif";
      field.style.font=`700 ${state.fontSize}px ${family}`;
      field.style.lineHeight='1.2';field.style.color=state.color;
      const ctx=this.engine.ctx;ctx.save();ctx.font=`bold ${state.fontSize}px ${family}`;
      const lines=(field.value||field.placeholder).split('\n');
      const width=Math.max(...lines.map(line=>ctx.measureText(line||' ').width));ctx.restore();
      field.style.width=`${Math.ceil(width)+4}px`;field.style.height=`${state.fontSize*1.2*lines.length}px`;
      field.style.left=point.x+'px';field.style.top=point.y+'px';
      field.style.transform=`scale(${point.scaleX},${point.scaleY})`;
    }
    commitText(){if(!this.textState)return;const field=this.q('.ax-image-editor__text');this.engine.addTextAt({...this.textState,text:field.value});this.textState=null;field.hidden=true;field.value='';}
    keydown(event){
      if(this.sending)return;
      const typing=event.target.matches('input,textarea'); const key=event.key.toLowerCase();
      if(key==='escape'&&this.textState){event.preventDefault();this.textState=null;this.q('.ax-image-editor__text').hidden=true;return;}
      if(typing){if(key==='enter'&&!event.shiftKey){event.preventDefault();event.target.matches('[data-caption]')?this.send():this.commitText();}return;}
      if((event.ctrlKey||event.metaKey)&&['z','y'].includes(key)){event.preventDefault();this.engine[key==='y'||event.shiftKey?'redo':'undo']();return;}
      const tool={c:'crop',b:'blur',t:'text',d:'draw',a:'arrow',r:'rect',o:'ellipse',e:'erase',v:'move'}[key];if(tool){event.preventDefault();this.engine.setTool(tool);}
    }
    async send(){
      if(this.sending)return;this.commitText();this.sending=true;const button=this.q('[data-command=send]');button.disabled=true;button.textContent='…';this.q('[data-error]').hidden=true;
      try {
        const blob=await this.engine.exportBlob('image/png');if(!blob||blob.size>10*1024*1024)throw new Error('A imagem editada excede 10 MB. Recorte a imagem antes de enviar.');
        const body=new FormData(this.form);body.delete('files[]');body.set('body',this.q('[data-caption]').value);body.append('files[]',new File([blob],this.file.name.replace(/\.[^.]+$/,'')+'-editada.png',{type:'image/png'}));
        const response=await fetch(this.form.action,{method:'POST',headers:{'X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content,'Turbo-Frame':'support_conversation'},body});
        const html=new DOMParser().parseFromString(await response.text(),'text/html');
        if(!response.ok)throw new Error(html.querySelector('[role=alert]')?.textContent||'Não foi possível enviar. Sua edição está preservada; tente novamente.');
        const incoming=html.querySelector('#support_conversation'), frame=document.querySelector('#support_conversation');
        if(!incoming||!frame)throw new Error('Confira sua sessão antes de tentar novamente. A edição está preservada.');
        try{sessionStorage.removeItem('unitymob-support:'+this.form.dataset.supportDraft);}catch(_){}
        const url=frame.src;frame.replaceChildren(...incoming.childNodes);frame.dataset.activeTab='conversation';if(url)frame.setAttribute('src',url);
        this.input.value='';this.close(true);frame.dispatchEvent(new CustomEvent('turbo:frame-load',{bubbles:true}));
      }catch(error){this.q('[data-error]').textContent=error.message;this.q('[data-error]').hidden=false;}
      finally{this.sending=false;button.disabled=false;button.innerHTML=icons.send;}
    }
    close(force=false){if(this.sending&&!force)return;window.removeEventListener('resize',this.onTextResize);this.engine?.destroy();this.engine=null;this.dialog.close();this.dialog.remove();document.body.classList.remove('ax-image-editor-open');active=null;this.previousFocus?.focus();}
  }
  document.addEventListener('change',async event=>{
    const input=event.target;if(!input.matches('form[data-support-image-reply] input[type=file]')||input.matches(':disabled')||active||input.files.length!==1)return;
    const file=input.files[0];if(!['image/jpeg','image/png','image/webp'].includes(file.type))return;
    const url=URL.createObjectURL(file);const img=new Image();
    try{img.src=url;await img.decode();if(input.isConnected&&!active){active=new AttachmentEditor(input,file,img);input.form.dataset.dirty='true';}}
    catch(_){/* Arquivo original permanece disponível para envio normal. */}
    finally{URL.revokeObjectURL(url);}
  });
  document.addEventListener('turbo:before-cache',()=>active?.close(true));
})();
