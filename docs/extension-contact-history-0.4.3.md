# Histórico de contatos na extensão 0.4.3

Formulário no bloco Histórico de contatos com Tipo de contato (Ligação, WhatsApp, E-mail, Visita, Nota interna), Resultado e descrição. As opções vêm das constantes LeadActivity usadas no CRM. Nota interna oculta, limpa e dispensa resultado. Os contatos exibem tipo, resultado, data, autor e descrição no histórico e usam a contagem existente de tentativas.

POST /api/v1/browser_extension/leads/:id/contacts: valida tipo/resultado, escopo do lead/tenant, permissão de edição, termos e confirmação do telefone; recibo idempotente impede duplicação. Endpoint /notes permanece compatível com a extensão antiga. Nenhuma mensagem externa é enviada pelo registro de contato.

Validação: 45 exemplos Rails e 48 testes JS, incluindo resultados, nota sem tentativa, escolhas inválidas, repetição, autorização, tenant e comportamento do select. Sem migrations. Fontes espelhadas no checkout local; pacote 0.4.3 preparado. Pasta instalada dist permanece 0.4.2 de produção até publicação do backend Salute/Conexão e troca do pacote. Central/Gateway não precisam de deploy.
