import {cp,mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const target='/tmp/unitymob-extension-tabs-preview';
await mkdir(target,{recursive:true});
await cp(resolve(root,'dist'),target,{recursive:true});
for(const file of ['bootstrap.js','catalog.js','property-workspace.js']) await cp(resolve(root,'preview',file),resolve(target,file));
const html=(await readFile(resolve(root,'dist/panel.html'),'utf8'))
 .replace('src="panel.js"','src="bootstrap.js"')

 .replace('<body>','<body style="max-width:420px;margin:auto"><aside style="padding:12px;font:12px/1.5 system-ui;background:#e9f7f7;color:#204d58">Layout da extensão · dados fictícios. Consultas simuladas para demonstração local. Nada é enviado ao CRM ou WhatsApp.</aside>');
await writeFile(resolve(target,'panel.html'),html);
console.log(`Prévia: ${target}/panel.html`);
