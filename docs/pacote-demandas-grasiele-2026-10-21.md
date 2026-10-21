# Pacote de demandas — Grasiele / Salute — 21/10/2026

Preparação local antes do deploy. Nenhum item desta rodada foi implantado; não
foram excluídos rascunhos nem reenviados leads. Preservar o WIP existente e não
incluir `outputs/`, credenciais ou caches de ferramentas no pacote de código.

## Correções preparadas

| Demanda | Correção / referência | Estado |
|---|---|---|
| Distribuição C2S | Configuração separada para venda/locação; corretor do C2S elegível ou fila como contingência; sem trocas intermediárias. `docs/c2s-lead-assignment.md`. | Preparada anteriormente; migration pendente de implantação. |
| Quatro rascunhos da Adriana | Libera referências com preservação dos históricos, escopo de conta e rollback; rotina compartilhada por captação, cadastro e DWV. | Preparada anteriormente; registros de produção intactos. |
| XML principal Imovelweb | Recupera gerador Vista/OpenNavent do projeto antigo, com identidade por tenant e streaming. `docs/imovelweb-vista-xml-2026-10-21.md`. | Preparado; aceitação real no portal ainda não comprovada. |
| 9780 não aparece no site | Status `Diária` passa a integrar a lista pública. Fotos, preço e opção de exibição continuam exigidos. | Preparado nesta rodada. |
| Preço da diária | `/dia` nos cards e no detalhe; não usa preço de venda remanescente; não soma condomínio/IPTU mensais à diária nem apresenta “Total mensal” ou “Taxas inclusas” por inferência. | Preparado nesta rodada. |
| Situação da captação | Reutiliza `Habitation::SITUATIONS`, como o administrativo; preserva opção antiga já selecionada ao editar. | Preparado nesta rodada. |
| Visibilidade/publicação de captação | Toggle Site bloqueado até primeira publicação pelo fluxo do corretor. Internas, devolvidas e aprovadas não podem ser publicadas pelo toggle ou por PATCH administrativo de `intake_status=published`. | Preparado nesta rodada. |

O filtro do Zap da Salute foi ajustado anteriormente por autorização específica,
sem deploy, para Venda/Aluguel. Não foi reaplicado nem ampliado para outros portais.

## Diagnóstico das novas correções

Consulta SQL READ ONLY confirmou o imóvel 9780 como `Habitation 23835`, tenant 1,
status `Diária`, `exibir_no_site_flag=true`, `intake_status=published` e modalidade
`locacao_diaria`. A exclusão vinha de `PUBLIC_STATUSES`, que não continha `Diária`.
O valor encontrado foi R$ 3.000,00; sua interpretação exibida passa a ser por dia.
Nenhum valor ou cadastro foi alterado em produção.

Situação: a captação mantinha uma lista própria de três valores; o cadastro usa
seis valores canônicos. A lista própria foi eliminada, mantendo o helper ax e
as mesmas dimensões/espaçamentos do formulário.

Visibilidade: o toggle desabilitava apenas `submitted_for_admin_review`, mas o
servidor também bloqueava `admin_approved` e outros estados; para `internal`, o
servidor permitia publicação direta. O seletor de status ainda oferecia
`published` ao revisor. Agora tela e servidor usam o mesmo predicado de domínio.
Captação já publicada e cadastro direto administrativo preservam seus fluxos.

## Impacto compartilhado

São mudanças sistêmicas, não condicionais da Salute. Aplicam-se às contas que
usam os fluxos corrigidos, mantendo consultas tenant-scoped e testes de limites.
A inclusão de `Diária` também alcança os consumidores de `PUBLIC_STATUSES`, como
catálogo público, sitemap e seleção pública/compartilhável; filtros de portais
continuam independentes e não foram flexibilizados.

Veredito dos temas: `default`, `saluteimoveis`, `conexaoimobiliaria` e
`salute_luxury` ajustados/cobertos pela regra compartilhada de diária. Há teste
parametrizado de listagem/detalhe/retirada para todos os temas. Sem SCSS alterado;
nenhum build CSS é necessário. Não houve redesign: markup e ritmo visual
existentes foram mantidos, mudando opções, estados e unidade do preço.

## Ainda pendentes

- Evento Google por etapa do funil, idempotência e integração GTM/STAPE.
- Confirmação real do processamento do XML pelo Imovelweb e autoria da baixa histórica do 8478.

As pendências não devem ser anunciadas como resolvidas nem incluídas em notas de
release como funcionalidades entregues.

## Validação desta rodada

- Rodada ampla: 934 exemplos. Encontrou duas regressões de seleção comercial
  causadas pela inclusão de `Diária` e três falhas estáticas preexistentes.
- As duas regressões foram corrigidas: a diária pode ser pública, mas continua
  excluída de `shareable_commercial_selection`, preservando o contrato anterior.
- Revalidação final de modelos, duas seleções em massa e todos os temas públicos:
  **118 exemplos, 0 falhas**. Inclui os ajustes finais de total mensal, título e
  tipo de negociação do contato de diária.
- Os demais testes de captação, cadastro, componentes públicos, portais e
  contratos passaram na rodada ampla, exceto os três contratos abaixo.
- `zeitwerk:check RAILS_ENV=test` e `git diff --check`: passaram.

Falhas estáticas preexistentes em `spec/lib/admin/dark_theme_component_contract_spec.rb`:
1. linha 3799: contrato da automação espera três painéis, mas a view contém dois;
2. linha 4203: matriz documental de componentes não acompanha o inventário CSS;
3. linha 1289: mapa de seletores não inclui `journey_explorer`.

Foram comparados com `git show HEAD:<arquivo>` os 105 arquivos de entrada
relevantes (teste, documentação, componentes CSS e views de automações): nenhum
foi alterado por esta preparação. Não foram ajustados apenas para deixar o teste
verde. A regressão geral permanece com essas três pendências registradas.

Limites: sem smoke visual em navegador nesta rodada; sem processamento externo
real de XML; sem deploy. Os testes de request exercitam o HTML e as regras em
cada tema, sem substituir homologação visual. Não foi alterado SCSS.

## WhatsApp público — preparado em 21/10, sem deploy

- Modal compartilhado valida com `libphonenumber-js/max` 1.12.24, vendorizado e carregado somente ao enviar. Sem país explícito, assume Brasil; outros países exigem `+DDI`. O input público deixa de usar a máscara permissiva que truncava internacionais/completava números antigos. Os demais formulários mantêm seu `phone-input`.
- `POST /leads` repete a validação com Phonelib 0.10.28 antes de intake, distribuição, webhook, e-mail ou conversão. Rejeita DDD inválido, telefone fixo brasileiro, sequência repetida e número incompleto; não acrescenta nono dígito.
- E.164 validado é salvo em `attribution_data.phone_e164`, retornado e encaminhado nos webhooks e no evento confirmado. `Lead#phone` mantém o contrato de dígitos do CRM. A normalização e a busca de contato respeitam esse E.164, evitando reinterpretar DDI em salvamentos/consultas posteriores; entradas sem esse metadado preservam o comportamento anterior.
- Rejeição HTTP 422 mostra erro junto ao campo; falha de transporte mantém os dados para nova tentativa. Ambos liberam o botão e não redirecionam nem emitem conversão. O evento `generate_lead` usa somente confirmação do servidor, após persistência; contatos internos e consultas complementares continuam sem novo evento. Mantido o consentimento do tracking existente.
- Corpus compartilhado Ruby/JS inclui Brasil (também DDD 55), Portugal, Argentina, EUA e Reino Unido. Validação estrutural não consulta cadastro real no WhatsApp.
- Chrome local: inválido rejeitado no campo, internacional alcança o servidor simulado e uma rejeição mantém o formulário; aceite simulado gera uma conversão. Persistência, reenvio/complemento e efeitos externos foram exercitados pelos testes Rails com webhooks/e-mails isolados. Nenhuma requisição de teste foi enviada a produção.

Validação do WhatsApp: rodada ampla com 120 exemplos Rails/0 falhas (inclui contrato dos quatro temas), rechecagem final de 63 exemplos/0 falhas após os ajustes de E.164 e DDD 55; 47 testes JavaScript/0 falhas, `zeitwerk:check` e `git diff --check` aprovados. Não foi repetida a suíte inteira; as três falhas estáticas anteriores do admin seguem fora desta correção.

## Upload de fotos — correção local preparada em 21/10

Investigação em [photo-upload-performance-2026-10-21.md](photo-upload-performance-2026-10-21.md). Removida preparação de versões públicas dos originais que aguardam marca (60 jobs evitados no teste com 20 fotos) e priorizada a conclusão da marca na fila de mídia. Uploads sem marca, qualidade, concorrência e isolamento das contas preservados. Sem deploy, manipulação de filas ou dados de produção. A redução real do tempo de espera em produção ainda não foi medida.

## Datas dos corretores — implementação local preparada em 21/10

Formulário e ficha usam os campos históricos existentes do Vista, com validação de datas e preservação em importações parciais. Disponível a todas as contas, inclusive sem Vista. Nenhuma data foi preenchida retroativamente, nem alterada regra de ativação/inativação ou distribuição. Detalhes e limite da precedência do dump em [broker-membership-dates-2026-10-21.md](broker-membership-dates-2026-10-21.md). Sem produção ou deploy.

## Calendário da diária — implementação local preparada em 21/10

Bloqueios internos com datas inclusivas e prevenção de sobreposição; consulta pública mensal nos quatro temas, com carregamento independente do cache da página. Disponível a todas as contas, com escopo/permissões do editor de imóveis. Migration pendente fora dos testes; sem deploy ou alteração em produção. Escopo e limites em [daily-rental-availability-2026-10-21.md](daily-rental-availability-2026-10-21.md).

## Google por etapa e comissão real — implementação local preparada em 21/10

Mapeamento opcional por etapa, destino Google explícito por conta, outbox criptografada e deduplicada por lead/tipo, tentativas limitadas e preservação dos eventos de entrada/GA4/Meta. Criado campo opcional de comissão real no fechamento (desktop/mobile), validado e auditado; somente o fechamento usa esse valor. Nenhuma ativação ou preenchimento retroativo. Detalhes em [google-funnel-events-2026-10-21.md](google-funnel-events-2026-10-21.md). Sem eventos reais, produção ou deploy; aceitação pelo receptor Google ainda não verificada.
