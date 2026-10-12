# Protocolos de assinatura

Protocolos distintos; não fundir automaticamente:

| Fluxo | Header | Bytes assinados | Ausência de secret |
| --- | --- | --- | --- |
| Meta → Gateway | X-Hub-Signature-256 | Corpo bruto, HMAC-SHA256, prefixo sha256= obrigatório | Rejeita |
| Meta → Plataforma | X-Hub-Signature-256 | Corpo bruto, HMAC-SHA256; parser atual tolera digest com/sem prefixo | Produção rejeita; fora dela tolera e registra aviso |
| Gateway → Plataforma | X-Unitymob-Gateway-Signature | Corpo bruto, HMAC-SHA256; emissor inclui sha256= | Não valida via Gateway; segue validação Meta |
| Plataforma → receptor externo | X-Unitymob-Signature + X-Unitymob-Timestamp | timestamp.corpo, HMAC-SHA256, sha256= | Envia sem assinatura, por compatibilidade |

Meta usa app secret de configuração do sistema com fallback ENV; encaminhamento usa `WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET`; saída usa resolução existente em `WebhookService.signing_secret`. Nunca documentar valores reais. Preservar corpo bruto (espaços, Unicode, quebras de linha). Receptor externo deve validar timestamp e definir janela antirreplay; a assinatura de saída não implementa essa política no receptor.

Fixture sintética comum: `spec/fixtures/contracts/webhook-signatures.json`, consumida nos testes da plataforma e Gateway. Payload alterado ou digest inválido deve ser rejeitado quando há secret. A tolerância de prefixo da plataforma é registrada, não alterada nesta extração.

Rotação: configuração de secrets continua local a cada aplicação e exige coordenação de emissor/receptor. Não existe nesta entrega aceitação simultânea de duas chaves. Deploy do Gateway é independente; `all` publica apenas Salute e Conexão, conforme docs/deploys.md.
