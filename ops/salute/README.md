# Operacao da Salute

Arquivos versionados para os ajustes de memoria do host de producao. A
instalacao deve preservar os nomes atuais das units e sempre ser seguida por
`systemctl daemon-reload`, reinicio controlado do servico afetado e smoke test.

- `salute-memory-guard`: evita reciclar repetidamente workers Puma durante um
  pico legitimo. Exige duas amostras, memoria disponivel de no maximo 30% e
  cooldown de cinco minutos.
- `solid-queue-runtime-memory.conf`: limita o cache Rails de cada processo do
  Solid Queue a 16 MB, sem alterar filas, threads ou prioridade operacional.
