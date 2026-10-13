# ADR-001 — Centralizar ajustes de IA em `/admin/ai_integration`

Data: 2026-10-13 · Status: aceito · Branch: `fix/ai-multi-provider`

## Contexto

Os ajustes de IA com inferência estavam em 4 telas: `/admin/ai_integration`
(provedor, conteúdo, voz), `/admin/property_settings` (~40 campos de busca),
`/admin/layout_settings` (inteligência de interesse) e `/admin/seo_settings`
(estratégia de SEO). Regras de params/normalização viviam inline nos
controllers e metadados de formulário soltos em views.

## Decisão

`/admin/ai_integration` vira o painel único, em 5 abas (Conexões e módulos, Conteúdo, Busca e voz,
Leads, Dados), sem duplicar nada — cada coisa tem uma fonte:

| Fonte única | Consumidores |
|---|---|
| `PropertySetting::AI_SEARCH_FORM_FIELDS` (params permitidos) | property_settings + ai_integrations |
| `admin/shared/ai/_property_search_settings` + `_property_search_sharing` | property edit + aba Busca e voz |
| `InterestIntelligence::Settings.normalize_*` + `NUMBER/WEIGHT/SAFEGUARD_FIELDS` | layout_settings + ai_integrations |
| `admin/shared/ai/_interest_intelligence_settings` | layout edit + aba Leads |
| `Seo::StrategySettings.save!` + `_seo_strategy_fields` | seo modal + aba Conteúdo |
| `Ai::SeoContentService.save_instructions!` (já existia) | reaproveitado via StrategySettings |

Ficam nas telas de origem (com link a partir da IA): aliases de
empreendimento e aprendizado supervisionado — operacional do domínio de
imóveis, não config de inferência. Sem aba "Outras": o único medidor de uso
(`OpenAiUsageEvent`) é do diagnóstico do BI, já exibido na aba Dados.

## Consequências

- Remoção das telas legadas (2026-10-13): os blocos saíram de
  `property_settings/edit`, `layout_settings/edit` e do modal de
  `seo_settings/index`; cada ponto exibe aviso + link para a aba
  correspondente da tela IA (link só com `manage :integracoes`).
  Params de IA enviados às rotas legadas são ignorados; o conteúdo já
  configurado (colunas + Setting keys) foi preservado sem migration.
- Hub de conexão (2026-10-13): credenciais e modelos de todas as
  capacidades saíram das abas para um bloco único acima delas
  (`section=provider_connection`, um card por provedor: matriz de
  capacidades → modelos → autenticação em cascata). Abas guardam só
  ajustes de comportamento. Conta do provedor via navegador (OAuth)
  desenhada como "Em breve": nem OpenAI nem Meta oferecem OAuth de
  terceiros para faturar API na conta do usuário; quando existir, o
  `dashboard_url` e o bloco de conta do card já são o ponto de
  integração — sem tocar nas abas.
- Autorização: os novos caminhos de escrita exigem `manage :integracoes`
  (permissão da tela IA), independente de `:configuracoes`, `:conta` e
  `:site_publico` das telas de origem. Quem tem só uma das permissões de
  origem continua usando a tela de origem.
- Badge "OpenAI" do bloco de parâmetros da busca virou "IA" (multi-provedor).

## Vínculos por módulo (2026-10-13)

A aba **Conexões e módulos** concentra credenciais e modelos padrão e os
vínculos por função. Seleção do provedor, modelos pré-preenchidos e autenticação ficam no mesmo
bloco. Ao escolher outro provedor, carregam-se as configurações já salvas
dele; sem configuração prévia, os modelos padrão formam o preset inicial.
Somente os campos do provedor selecionado ficam visíveis e habilitados.
A matriz de uso por módulo vem depois, para exceções ao padrão da conta,
sem interromper a configuração da conexão. A matriz permite
herdar esse padrão ou escolher outro provedor e modelo para conteúdo de
imóveis, SEO, busca por texto, interpretação de voz, transcrição, resumo de
interesse e diagnóstico do BI. As outras abas exibem os vínculos salvos para
consulta e preservam instruções, regras, permissões e limites.

`Ai::ModuleConfiguration` é a fonte única dos módulos e da resolução de
provedor, credenciais, modelo e fallback. Os vínculos são gravados em
`Setting` com a chave `ai_module_bindings`, exclusivamente no tenant.
Campos vazios herdam os modelos e tokens existentes, sem migration ou
backfill. Interpretação e transcrição usam o token dedicado de voz do mesmo
provedor quando configurado. Todos os consumidores, incluindo busca pública
por texto/voz e lote de imóveis, usam essa resolução. O cache do diagnóstico
do BI inclui provedor e modelo, mantendo cotas e histórico de uso da conta.

Conexões e vínculos são salvos na mesma transação. Modelos personalizados são
obrigatórios quando selecionados e limitados a 200 caracteres sem espaços;
provedores desconhecidos são rejeitados. Provedores ocultos não são enviados
pelo formulário. A autenticação pelo navegador continua indisponível.

Na matriz, cada módulo exibe apenas o provedor e modelo herdados. O switch
“Configurar exceção” revela os seletores manuais; exceções já salvas aparecem
ativadas. Desativar o switch limpa o vínculo específico ao salvar. O resumo
acompanha as alterações do preset e dos modelos em tempo real, sem alterar
os valores salvos até a confirmação do formulário.

## Organização da aba Conteúdo (2026-10-13)

A aba tem três seções em sequência: Conteúdo dos imóveis, SEO do site e
Geração em lote. Conteúdo e SEO mantêm formulários e salvamentos separados.
Provedor e modelo são links compactos no cabeçalho de cada configuração;
credenciais e vínculos continuam em Conexões e módulos. Os editores usam a
partial compartilhada `admin/shared/ui/expandable_textarea`; expandir ou
recolher muda apenas a altura, preservando o texto. Parâmetros de geração
ficam em Ajustes avançados e continuam sendo enviados mesmo recolhidos.

SEO distingue inventário/descoberta, geração por IA e aplicação no site.
O aviso de revisão manual pertence ao lote de imóveis. O lote conserva
job, confirmação, contadores, mensagens e última atualização; traduz seu
status e mostra progresso depois de iniciado. Sem token de conteúdo, a
interface mostra o requisito e desabilita o início; o controller mantém a
mesma validação de conexão. Nenhuma nova aba interna ou mudança de domínio.
