# Deploy do site institucional Unitymob

Confirmado em produção em 06/09/2026: HTTPS `unitymob.com.br` e `www.unitymob.com.br`, host `72.61.221.253`, SSH `root@72.61.221.253`, Apache, DocumentRoot `/var/www/html/unitymob.com.br`.
Fonte: `public/site/`. Não é aplicação Rails e não usa Mina. A origem é publicada na raiz do domínio (sem `/site/`).

## Escopo

- Site institucional: procedimento abaixo.
- Alterações Rails em cookies/consentimento: publicar separadamente Salute e Conexão com Mina, conforme `docs/deploys.md`.
- Não reiniciar Central, Gateway ou Apache para atualizar HTML/CSS/JS estático.
- Não publicar arquivos `index.backup*`, backups, `.env`, relatórios internos ou documentação operacional.

## Preparação

Identificar o pacote autorizado, preservar WIP externo, testar e publicar uma revisão em `origin/master`. Use checkout isolado se o checkout principal tiver alterações de outras tarefas. Confirme os remotos novamente antes de promover para evitar sobrescrever publicação concorrente. Não use force push.

```bash
git fetch origin
site_revision=$(git rev-parse origin/master)
site_package=$(mktemp -d /tmp/unitymob-site.XXXXXX)
git archive "$site_revision" public/site/index.html public/site/politica-de-privacidade.html public/site/opcoes-de-privacidade.html public/site/termos-de-uso.html public/site/assets | tar -x -C "$site_package"
```

Conferir que os três documentos legais, a home e seus assets constam do pacote. Links relativos precisam funcionar na raiz do domínio. Usar `node --check` nos scripts e conferir HTML/links. Para alterações Rails, executar os testes específicos e Zeitwerk.

## Backup e dry-run

```bash
ssh root@72.61.221.253 'install -d -m 700 /var/lib/unitymob-site/backups; tar -czf /var/lib/unitymob-site/backups/site-$(date -u +%Y%m%dT%H%M%SZ).tar.gz -C /var/www/html unitymob.com.br'
rsync -rlptzn --itemize-changes --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r "$site_package/public/site/" root@72.61.221.253:/var/www/html/unitymob.com.br/
```

Conferir o backup com `tar -tzf` e registrar o nome exato para rollback. O backup fica fora do diretório público. Não usar `--delete`: arquivos do servidor não pertencentes ao pacote devem ser avaliados separadamente.

## Publicação

Publicar assets antes do HTML. `--delay-updates` prepara arquivos temporários e só substitui cada arquivo após a transferência; não é troca atômica da árvore inteira.

```bash
rsync -rlptz --delay-updates --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r "$site_package/public/site/assets/" root@72.61.221.253:/var/www/html/unitymob.com.br/assets/
rsync -rlptz --delay-updates --chmod=Fu=rw,Fgo=r "$site_package/public/site/"*.html root@72.61.221.253:/var/www/html/unitymob.com.br/
```

O glob acima é seguro porque o pacote foi criado com apenas os quatro HTML explicitamente permitidos. Não executar contra `public/site` local, que contém backups antigos.

## Validação

- Confirmar 200 e `Content-Type` em `/`, `/politica-de-privacidade.html`, `/opcoes-de-privacidade.html`, `/termos-de-uso.html`.
- Comparar SHA-256 do conteúdo HTTP de cada HTML e asset com o pacote; usar query com a revisão para evitar cache antigo.
- Conferir domínio `www`, imagens, CSS, navegação legal e abrir a página real no browser.
- Verificar seletor das demonstrações e abertura do diagnóstico sem enviar mensagens reais.
- Não enviar formulário, aceitar termos em nome de clientes ou criar dados de CRM como smoke test.
- Apenas após sucesso registrar a revisão fora do DocumentRoot:

```bash
printf '%s\n' "$site_revision" | ssh root@72.61.221.253 'cat > /var/lib/unitymob-site/deployed_revision'
```

## Rollback

Selecionar o backup exato registrado antes da publicação. Inspecionar o arquivo e restaurar somente o site:

```bash
ssh root@72.61.221.253 'tar -tzf /var/lib/unitymob-site/backups/ARQUIVO_CONFIRMADO.tar.gz'
ssh root@72.61.221.253 'tar -xzf /var/lib/unitymob-site/backups/ARQUIVO_CONFIRMADO.tar.gz -C /var/www/html'
```

O restore repõe arquivos anteriores; novos assets podem permanecer sem referência. Não apagar arquivos desconhecidos. Revalidar HTTP e aparência; restaurar o marcador da revisão anterior se conhecido. Um rollback estático não desfaz deploy Rails.
