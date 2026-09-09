# Armazenamento de desenvolvimento

Novos blobs em Rails development usam `development_sandbox`, no bucket privado
`unitymob-development-media`. Mesmo uploads que informem serviços de uma cópia de
produção são redirecionados antes da criação do blob. As credenciais continuam
nas variáveis locais existentes; nenhuma credencial foi adicionada ao repositório.

Serviços S3/Spaces antigos são registrados como DevelopmentReadOnlyS3 apenas em
development: download continua permitido; upload, URL de upload e composição são
bloqueados. Exclusões de objetos e de variantes são ignoradas no serviço remoto,
permitindo remover o vínculo do banco local sem apagar arquivos compartilhados.
A publicação de ACL também só é permitida para blobs do sandbox em development.
Essa proteção cobre Active Storage e o fluxo de publicação de fotos; não é uma
política IAM aplicada às credenciais nem protege scripts externos usando AWS SDK.

Produção e teste mantêm seus serviços existentes. Após mudar os initializers,
reiniciar o servidor e workers de desenvolvimento é obrigatório.

Worker dedicado para validar mídia sem executar filas de mensagens/recorrências:

```
rvm 3.2.3 do bundle exec ruby bin/jobs start --mode=async --config-file=config/queue_media_development.yml --skip-recurring
```

Validação realizada: upload e download reais no sandbox (mesmo com serviço antigo
solicitado), processamento de PNG com marca, persistência e download do resultado,
remoção somente dos artefatos de teste. Specs de serviço read-only, registro de
serviços e segurança do job de marca passaram; Zeitwerk passou.

Buckets de produção não foram alterados. Não redefinir os serviços antigos para
apontarem ao sandbox: isso impediria a leitura dos arquivos importados.
