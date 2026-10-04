# Recuperação Salute e Conexão

`install-recovery.sh salute|conexao` aplica drop-ins systemd, preserva as units e
salva backup em `/var/backups/unitymob-recovery-*`. Não reinicia serviços saudáveis.
Puma/fila reiniciam em cinco segundos ao encerrar; banco, cache e Nginx voltam
em falhas. Cinco tentativas por minuto evitam crash loops de configuração.

O timer sonda `/healthz` local a cada minuto: três falhas consecutivas permitem
recuperar Puma indisponível ou fila sem heartbeat, com cooldown de quinze minutos.
Uma falha declarada de banco/cache não provoca restart do Puma. O monitor não
corrige configuração inválida, disco cheio ou corrupção de dados.

Durante deploy, `shared/tmp/deploy-in-progress` suspende os guards por até dez
minutos. Em manutenção manual, mascarar a unit de aplicação ou parar ambos os
timers e o guard; reativar ao terminar. `journalctl -u unitymob-service-recovery`
mostra diagnóstico e ações; estado/cooldown ficam em `/run/unitymob-service-recovery`.

Conexão recebe os limites já usados na Salute: Puma High 2200M/Max 2600M,
fila High 2400M/Max 3200M. O guard existente exige duas amostras de pressão,
limita reciclagem de worker e aplica cooldown. Não aumenta concorrência ou filas.

O deploy Mina aguarda saúde de banco/cache/fila e aquece home/listagem da conta.
HTML público usa a revisão da release na chave; nenhum flush global Redis é feito.
Configurações compartilhadas e demais caches permanecem intactos.

Verificação local: `python3 ops/shared/test_service_recovery.py`.
Rollback: remover as units/timer e os drop-ins `zzzz-recovery.conf` instalados,
restaurar as configurações do backup e executar `systemctl daemon-reload`.
