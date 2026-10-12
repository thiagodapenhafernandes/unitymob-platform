# Execução incremental da auditoria

Base: `c81db8ae`. Esta primeira implementação cobre os seis passos acordados, com recorte específico de imóveis e sem refatoração global.

| Etapa | Entrega | Estado |
| --- | --- | --- |
| Preparação | Índice canônico, responsabilidades e contratos atuais | Implementado |
| Contatos internos | Query comum para dashboard e cleanup, matching preservado | Implementado |
| XLSX | Writer do dashboard; relatório comercial permanece separado por contrato | Implementado |
| Aceite | Serviço comum para admin, link e WhatsApp; dono/status sob lock; efeitos em transação | Implementado |
| Integrações | Contratos de ingresso/base legal/assinaturas e fixture comum Plataforma/Gateway | Implementado |
| Imóveis | Serviço de publicação em lote, preservando opções, auditoria e caches | Primeiro recorte implementado |

Validação local: 404 exemplos dos fluxos afetados; 57 exemplos de contratos/serviços; 1 teste de concorrência com conexões reais; 1 teste puro de assinatura do Gateway; 47 exemplos do gate `RAILS_ENV=test bundle exec rake security:tenant_isolation`; Zeitwerk. Paridade XLSX byte a byte com implementação anterior e relógio fixado. Resultados não equivalem a verificação de produção.

A suíte com banco do Gateway foi bloqueada pelo guard de ambiente: o banco configurado não termina em `_test`. Não alterar essa proteção para forçar testes. Teste puro compartilhado executado sem banco.

Continuidade: métricas adicionais do dashboard e outras operações de imóveis são novos recortes, cada um com caracterização própria. Nenhuma alteração de importadores, callbacks gerais, normalização de telefones, temas públicos ou empacotamento foi necessária. Instalação da skill proposta permanece fora desta entrega.

Sem migration, limpeza de dados, chamadas externas reais ou deploy. As alterações podem ser revertidas por commit, sem backfill.
