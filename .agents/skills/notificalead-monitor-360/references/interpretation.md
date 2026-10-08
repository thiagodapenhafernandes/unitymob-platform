# Interpretacao do Snapshot 360

Use este arquivo quando precisar transformar a saida do snapshot em diagnostico.

## Sinais esperados

- `duplicate_active_keys = 0`: nao ha duas rotas ativas para a mesma chave.
- `active_accounts: ["cyrela"]` no AWS: a instancia esta coerente.
- `non_cyrela_recent_leads = 0` no AWS: nenhuma conta do legado vazou para AWS.
- `overdue_queued_leads = 0`: nao ha represamento fora da tolerancia.

## Sinais que pedem investigacao

- `unrouted > 0`: pode ser webhook de teste, WABA sem rota ou chave Meta nao
  cadastrada. Olhar eventos recentes antes de classificar como incidente.
- Muitas rotas para `cyrela-account`: nao e erro sozinho. Validar se vieram da
  conta Cyrela.
- `cyrela_active: true` no legado: pode ser dado historico/fallback; o que nao
  pode acontecer e o legado reassumir rotas Cyrela no gateway.

## Fluxo de incidente de lead

1. Obter `leadgen_id`, `form_id`, `page_id`, nome do lead e horario.
2. Consultar gateway por essas chaves.
3. Verificar onde o evento foi encaminhado.
4. Verificar onde o lead foi criado.
5. Verificar distribuicao, responsavel atual, token/link seguro e WhatsApp.
