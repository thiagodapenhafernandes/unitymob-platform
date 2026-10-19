# Revisão de SEO: URLs, canonical, sitemap e empreendimentos

Data: 18/10/2026. Status: implementação local para revisão; nenhuma publicação autorizada ou executada.

## Escopo e preservação

A correção está nos serviços, layout e componentes compartilhados. Não há condição por domínio, conta ou nome de empreendimento. Os quatro temas atuais e futuros consumidores desses componentes recebem a regra. Não foram alterados slugs, cadastros editoriais, filtros, status, permissões ou dados em produção. Android e teste administrativo que já estavam modificados ficam fora deste pacote.

## Antes e depois das regras

| Caso | Antes | Depois |
| --- | --- | --- |
| Home com `?class=absolute&data[action]=click&v=old` | Podia declarar canonical para essa variação | Canonical aponta para a home no domínio público da conta |
| Descoberta automática desativada | Fallback podia usar a URL completa visitada | Mesma normalização do restante do sistema |
| Registros SEO antigos com parâmetros de interface | Podiam continuar emitindo variantes | Leitura normalizada, sem apagar registros ou histórico |
| Filtros múltiplos, `page`, `sort` | Precisam manter seu significado | Preservados na normalização; paginação testada |
| Sitemap com tipo SEO legado incorreto | Política podia depender do tipo registrado | Política aplicada pela rota real |
| Imóvel com `noindex` ativo | Podia reaparecer pelo inventário de imóveis | Excluído também dessa origem |
| Cache do sitemap | Versão anterior | Nova chave, sem limpeza destrutiva |
| Título automático do empreendimento | Limite interno podia retirar toda a localização | Nome, bairro/cidade e oferta real, com a marca |
| Descrição automática | Podia terminar no meio de uma informação | Seleção de frases completas dentro do limite existente |
| Oferta do empreendimento | Texto genérico | Venda/locação conforme unidades públicas da própria conta |
| FAQ no luxury | Schema sem perguntas visíveis | Componente compartilhado com as mesmas perguntas e respostas |

A normalização muda a identidade canônica, não a requisição visitada: os parâmetros de campanha continuam disponíveis para atribuição, e o fluxo existente de URLs amigáveis `v=2` foi preservado. O sitemap não passa a indexar todas as combinações de filtros. Slugs históricos, mesmo com grafia imperfeita, continuam iguais.

## Cinco páginas prioritárias: prévia do mesmo banco local

Comparação executada entre o gerador anterior de `HEAD` e a implementação atual, usando os mesmos registros da Salute (`tenant_id=1`) no banco local `unitymob_platform_development`, host `localhost`. Não são uma leitura atual do estoque de produção nem uma previsão do texto que o Google escolherá exibir. Campos manuais desses empreendimentos foram preservados.

### Caledônia Private Village

URL preservada: `/empreendimento/caleda-nia-private-village`.

**Título anterior:** Caledônia Private Village em Camboriú | Salute imóveis

**Título novo:** Caledônia Private Village em Santa Regina, Camboriú: imóveis à venda | Salute imóveis

**Descrição anterior:** Conheça o Caledônia Private Village em Santa Regina, Camboriú. Empreendimento Glaffitte. Unidades disponíveis com 210 a 1271 m² de área privativa, 1 a 5

**Descrição nova:** Caledônia Private Village em Santa Regina, Camboriú. Confira imóveis à venda. 210 a 1271 m² de área privativa, 1 a 5 suítes, 2 a 4 vagas.

### Reserva Camboriú Golf Club

URL preservada: `/empreendimento/reserva-camboria-golf-club`.

**Título anterior:** Reserva Camboriú Golf Club em Centro, Camboriú | Salute imóveis

**Título novo:** Reserva Camboriú Golf Club em Centro, Camboriú: imóveis à venda | Salute imóveis

**Descrição anterior:** Conheça o Reserva Camboriú Golf Club em Centro, Camboriú. Empreendimento Reserva Camboriú. Unidades disponíveis com 370 a 740 m² de área privativa, 3 a 5

**Descrição nova:** Reserva Camboriú Golf Club em Centro, Camboriú. Confira imóveis à venda. 370 a 740 m² de área privativa, 3 a 5 suítes, 2 a 6 vagas.

### Residencial Haras Rio do Ouro

URL preservada: `/empreendimento/residencial-haras-rio-do-ouro`.

**Título anterior:** Residencial Haras Rio do Ouro | Salute imóveis

**Título novo:** Residencial Haras Rio do Ouro em Ariribá, Balneário Camboriú: imóveis à venda e para alugar | Salute imóveis

**Descrição anterior:** Conheça o Residencial Haras Rio do Ouro em Ariribá, Balneário Camboriú. Unidades disponíveis com 328 a 982 m² de área privativa, 4 a 5 suítes, 3 a 5 vagas.

**Descrição nova:** Residencial Haras Rio do Ouro em Ariribá, Balneário Camboriú. Confira imóveis à venda e para alugar. Consulte fotos, valores e disponibilidade.

### Riviera Concept

URL preservada: `/empreendimento/riviera-concept`.

**Título anterior:** Riviera Concept em Praia Brava, Itajaí | Salute imóveis

**Título novo:** Riviera Concept em Praia Brava, Itajaí: imóveis à venda | Salute imóveis

**Descrição anterior:** Conheça o Riviera Concept em Praia Brava, Itajaí. Empreendimento Riviera. Unidades disponíveis com 91 a 134 m² de área privativa, 2 a 3 suítes, 5 vagas.

**Descrição nova:** Riviera Concept em Praia Brava, Itajaí. Confira imóveis à venda. 91 a 134 m² de área privativa, 2 a 3 suítes, 5 vagas.

### Brava Garden - Home Club

URL preservada: `/empreendimento/brava-garden-home-club`.

**Título anterior:** Brava Garden - Home Club em Praia Brava, Itajaí | Salute imóveis

**Título novo:** Brava Garden - Home Club em Praia Brava, Itajaí: imóveis à venda | Salute imóveis

**Descrição anterior:** Conheça o Brava Garden - Home Club em Praia Brava, Itajaí. Empreendimento CN Construtora. Unidades disponíveis com 77 a 80 m² de área privativa, 1 suítes,

**Descrição nova:** Brava Garden - Home Club em Praia Brava, Itajaí. Confira imóveis à venda. 77 a 80 m² de área privativa, 1 suíte, 1 a 2 vagas.

## Temas

| Tema | Veredito |
| --- | --- |
| `default` | Ajustado pela camada comum, incluindo FAQ compartilhado |
| `saluteimoveis` | Ajustado pela mesma camada; prévia desktop aberta no Chrome |
| `conexaoimobiliaria` | Ajustado pela mesma camada, sem exceção por domínio |
| `salute_luxury` | Ajustado: resumo e FAQ visíveis, aparência e espaçamento próprios |

A prévia local da Caledônia está em <http://127.0.0.1:3135/empreendimento/caleda-nia-private-village?tenant=salute>. Imagens ausentes no armazenamento local não foram substituídas. Testes de integração percorrem todos os temas registrados. Visual desktop da Caledônia conferido. A prévia abriu em 390×844, mas o navegador atingiu timeout ao focar o FAQ; homologação visual completa do FAQ mobile e do luxury permanece pendente.

## Validação

- Rodada focal: 105 exemplos, zero falhas, cobrindo metadados, isolamento de estoque por conta, campos editoriais, sitemap, múltiplos filtros, URLs amigáveis, paginação, blog e empreendimentos.
- Contratos públicos e bibliotecas: rodada com 394 exemplos, 3 falhas em contratos administrativos estáticos; testes públicos passaram. Falhas reproduzidas isoladamente, sem carregar Rails, em arquivos não alterados por este pacote: formulário de regras espera três painéis e tem dois; matriz documental não corresponde ao inventário administrativo; `journey_explorer` está ausente do mapa de seletores do contrato.
- `npm run build:css`: passou.
- `rvm 3.2.3 do bundle exec rails zeitwerk:check`: passou.
- `git diff --check`: passou.
- Rodada consolidada final: 494 exemplos, 491 passaram; somente as mesmas três falhas administrativas acima.
- Último ajuste do sitemap: seleção apenas das colunas de URL e proteção para registros sem endereço; 11 exemplos, zero falhas.

## Limites e sequência para publicação

Sem migrations, backfill, exclusão de URLs no Search Console ou alteração de produção. O deploy deve acontecer somente após revisão deste pacote. Depois de publicado, validar a canonical das URLs com parâmetros e o sitemap no domínio real, comparar o estoque real das cinco páginas e acompanhar o recrawl no Search Console. A lista histórica de duplicadas não desaparece imediatamente.

Não foi feita limpeza indiscriminada dos 404/5xx históricos ou indexação de páginas com `noindex`. Não foram reescritas informações factuais dos condomínios, preços ou descrições editoriais sem conferência de origem. Ganho de posição depende também de conteúdo, concorrência e sinais externos; esta entrega não garante posição 1.
