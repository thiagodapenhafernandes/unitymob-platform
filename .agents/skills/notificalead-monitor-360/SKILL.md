---
name: notificalead-monitor-360
description: Use quando o usuário pedir monitoramento, healthcheck, validação 360 ou diagnóstico ponta a ponta da rede NotificaLead com gateway, proxy global, legado e Cyrela AWS.
---

# Notificalead Monitor 360

Faça uma validação operacional ponta a ponta da arquitetura NotificaLead. O foco
é detectar inconsistência real, não só responder "200 OK".

## Topologia Atual

- Gateway Meta: `webhooks.notificalead.com.br` / `54.94.168.195`.
- Proxy global: `56.126.45.58`.
- Legado: `account.notificalead.com.br` / `143.198.180.223`.
- Cyrela AWS: `cyrela-account.notificalead.com.br` / `54.207.220.132`.
- Regra operacional: somente `cyrela` deve estar ativa no AWS; demais contas
  continuam no legado.

## Execução Rápida

Se estiver no checkout `/Users/thiagodap.fernandes/worksapces/notificalead`,
rode:

```bash
bash scripts/notificalead_360_snapshot.sh
```

Se estiver fora do checkout, use o helper da skill:

```bash
bash ~/.codex/skills/notificalead-monitor-360/scripts/run_snapshot.sh
```

Leia também `docs/ops_360_monitoring_runbook.md` se precisar explicar o
processo, investigar incidente ou orientar outro agente.

## Como Interpretar

Considere saudável quando:

- HTTP público responde 200 para gateway, proxy, legado e Cyrela.
- `duplicate_active_keys = 0` no gateway.
- Gateway não acumula `ambiguous`, `bad`, `retryable` ou `unrouted` em volume
  crescente sem explicação.
- AWS retorna `active_accounts: ["cyrela"]`.
- AWS retorna `non_cyrela_recent_leads: 0`.
- Legado continua com contas ativas e recebendo leads não-Cyrela.
- Healthchecks remotos terminam com `OK stack healthcheck finished`.

Classifique como crítico quando:

- Lead não-Cyrela aparece no AWS.
- Lead Cyrela novo aparece somente no legado.
- Chave ativa duplicada no gateway aponta para destinos diferentes.
- Evento Meta fica `ambiguous`, `unrouted` ou `retryable` em crescimento.
- Pico de 502, 406, 506 ou 5xx aparece no proxy/servidores.
- Sidekiq está vivo mas filas ou leads represados passam do limite operacional.
- WhatsApp é aceito pela Meta, mas o link seguro já nasce inválido para o
  responsável atual.

## Diagnóstico

Ao responder, separe:

- **Estado atual:** principais OK/falhas com números.
- **Risco:** impacto prático, especialmente lead indo para servidor errado.
- **Evidência:** chave, conta, rota, status, fila, host ou horário.
- **Próximo passo:** comando/verificação/correção mínima.

Não conclua que `cyrela-account` está errado só porque há muitas rotas para ele.
O destino raiz do servidor AWS é esse mesmo; o erro é rota ou dado de conta
errada apontando para esse destino.

Não faça mutação em produção só por usar esta skill. Para correção, confirme a
causa e respeite o pedido explícito do usuário.
