# Extensão 0.4.1 — agenda, etiquetas, imóveis e status

Base: 72653a7576b2cdce477c5780fbac166cccf56753. Implementação local na branch codex/whatsapp-extension; ainda não publicada.

## Pacote para publicação

- Card compacto de identificação do lead e botões de ações menores, usando componentes compartilhados com modificadores explícitos.
- Agenda inline: título, tipo, início, término e local opcionais; compromisso associado ao lead e usuário conectado, com validação, auditoria e proteção contra duplicação.
- Seleção inline das etiquetas existentes do corretor com cores padrão ou hexadecimais. Catálogo privado e escopado ao tenant; aplicar/remover somente etiquetas próprias, preservando as de outros usuários. Catálogo vazio orienta cadastro no CRM; não cria novas etiquetas automaticamente.
- API: POST /api/v1/browser_extension/leads/:id/appointments e POST /api/v1/browser_extension/leads/:id/labels; dados do catálogo na consulta do lead.
- Termos v3 incluem compromissos, etiquetas, imóveis e alteração de etapa e exigem novo aceite, preservando a sessão ainda válida.
- Propostas removidas da interface da extensão.
- Imóveis: busca por venda/locação e código, nome ou localização; até 20 resultados por busca e seleção múltipla. Apenas catálogo disponível do tenant, sem captações em rascunho; vínculos idempotentes preservam o imóvel principal e os interesses anteriores.
- POST /api/v1/browser_extension/leads/:id/properties/search e POST /api/v1/browser_extension/leads/:id/properties.
- Alterar status diretamente no card do lead: opções do funil atual, com permissões de edição, visibilidade e transições permitidas. Mantém auditoria e automações do modelo; bloqueia alteração se a etapa tiver mudado desde a consulta e protege retries contra duplicação. POST /api/v1/browser_extension/leads/:id/status.
- Manifesto 0.4.1, builds apontando para Gateway e domínios de produção.

## Alvos

Salute (tenant 1, https://saluteimoveis.com.br, salute@143.110.138.67, /home/salute/deploy) e Conexão (tenant 72, https://app.conexaobc.com, conexao@app.conexaobc.com, /home/conexao/deploy). Gateway e Central não precisam de publicação. Não há migrations novas nem mudança de credenciais.

## Arquivos

app/assets/stylesheets/admin/components/operational_panel.css; app/controllers/api/v1/browser_extension/{base,leads,operations}_controller.rb; app/models/browser_extension_grant.rb; config/routes.rb; spec/requests/api/v1/browser_extension_spec.rb; browser-extension/package*.json; browser-extension/src/{background.js,panel.js,panel.html,panel.css}; browser-extension/test/background.test.js; este documento.

Ficam fora: alterações de filtros de exclusão, mobile e demais documentos operacionais não relacionados.

## Validação realizada

39 exemplos Rails da API e 43 testes JavaScript, sem falhas. Zeitwerk, sintaxe JavaScript, IDs únicos no HTML, botões inline e build passaram. Sem gravações em leads reais. A inspeção visual automatizada não foi realizada nesta rodada.

## Publicação

Commit seletivo do pacote acima, promoção develop/master preservando WIP independente e push sem força. Publicação dos dois CRMs: `rvm 3.2.3 do bundle exec mina all deploy`. Conferir revisões, Puma/Solid Queue, /up, rotas protegidas e telas adjacentes. Depois copiar dist-discovery para dist e recarregar a extensão no Chrome; aceitar termos atualizados e validar no atendimento escolhido pelo usuário.

O ZIP está em browser-extension/unitymob-whatsapp-discovery-0.4.1.zip. A pasta dist atualmente instalada foi preservada até a publicação da API.
