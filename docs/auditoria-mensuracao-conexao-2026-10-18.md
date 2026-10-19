# Mensuração Conexão BC — 18/10/2026

## Configurações aplicadas em produção

- GA4 existente preservado: propriedade 431425110, fluxo 7627098823, medição G-WX6W71NGHX. URL do fluxo corrigida do domínio antigo para https://conexaobc.com.
- Propriedade de domínio conexaobc.com do Search Console vinculada ao fluxo GA4.
- Site conectado ao container acessível GTM-PFC2LD5G; versão 3 publicada, nome “Conexão BC - GA4 e preservação Google Ads”. Não foi necessário criar outro container.
- Tag GA4 existente preservada. Tag de eventos adicionada para whatsapp_click e contact_click, com parâmetro business_type da camada de dados. Cliques não foram marcados como leads.
- Container anteriormente instalado GTM-W942D8JG preservado por tag de compatibilidade: carrega somente com unitymob_lgpd_consent=accepted e se ainda não estiver no documento. Mantém Google Ads AW-16492801046. Esse container continua sem acesso administrativo nesta conta.
- Meta permaneceu na configuração existente do site.

## Validação observada

- Com consentimento temporário autorizado: uma requisição GA4 page_view na navegação de validação; scripts dos dois containers, Google Ads e Meta carregados.
- Dois acionamentos de teste do botão de WhatsApp produziram dois whatsapp_click, business_type=venda, enviados ao destino correto; resposta HTTP 204. Nenhum formulário foi enviado e nenhum lead de teste foi criado.
- Rejeição de cookies restaurada e página recarregada: zero requisições de trackers na navegação observada.
- Configuração do site exibiu confirmação de salvamento; GTM exibiu versão 3 ativa.
- Não foram publicados os ajustes locais de URLs, canonical, sitemap e conteúdo SEO. Nenhum deploy de código foi feito nesta etapa.

## Lacunas e próximos passos

1. O recebimento HTTP confirma entrega de coleta, não disponibilidade de todos os relatórios processados. Conferir relatórios GA4 após processamento e excluir as próprias visitas de auditoria das interpretações de negócio.
2. contact_click foi configurado, mas não recebeu teste individual nesta rodada. O teste de whatsapp_click não valida conversão de lead.
3. Eventos do rastreador interno (ex.: property_card_click) usam endpoint próprio e não chegam automaticamente ao GA4. Centralizar o encaminhamento no ponto compartilhado de tracking, respeitando consentimento e evitando duplicação.
4. lead_created existe no servidor; o fluxo de formulário não emite generate_lead no navegador após sucesso confirmado. Implementar emissão após criação bem-sucedida, preservando a distinção entre lead novo/reutilizado e sem dados pessoais no GA4. Cobrir todos os temas e fluxos de contato.
5. Registrar dimensões necessárias para relatórios (business_type e, após integração, código público do imóvel e origem do componente). Não enviar nome, telefone ou e-mail.
6. Reconciliar leads qualificados e vendas do CRM por origem; clique em WhatsApp mede intenção, não atendimento ou venda. Essa integração não foi executada.
7. Recuperar administração de GTM-W942D8JG ou migrar suas conversões de Ads após conferência com a conta Ads. A compatibilidade atual é uma dependência transitória; não remover antes dessa validação.
8. Auditar Salute separadamente: as configurações desta entrega são da Conexão BC.

## Uso dos dados

Comparar janelas completas de 28 dias com o período anterior: impressões, cliques, CTR e posição por consulta/página no Search Console; sessões orgânicas, interações, leads confirmados e qualificados no GA4/CRM. Separar marca e consultas comerciais. Priorizar páginas de alta impressão nas posições 4–10 com estoque e intenção comercial. Não interpretar rejeição de cookies como falha de implementação nem prometer posição 1,0 com base na instalação do Analytics.

## Reversão

Para reverter a troca do site, restaurar GTM-W942D8JG no admin de Rastreamento. A versão anterior do container acessível continua no histórico. Isso restaura o cenário anterior de Ads, mas também perde a conexão GA4 adicionada nesta entrega.
