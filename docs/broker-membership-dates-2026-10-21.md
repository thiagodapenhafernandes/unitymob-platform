# Datas de entrada e saída dos corretores — 21/10/2026

Implementação local, compartilhada por todas as contas. Sem deploy, importação,
backfill ou alteração de registros em produção. Não exige migration.

## Dados e comportamento

- Reutilizados `admin_users.source_created_on` e `source_departed_on`, já existentes
  e mapeados do dump Vista `CADEMP.DATA` e `CADEMP.DATA_SAIDA`. Não se usa
  `created_at` da Unitymob para presumir entrada na imobiliária.
- Formulário administrativo exibe/edita “Data de entrada” e “Data de saída”; a
  ficha exibe ambas. Campos opcionais também funcionam em contas sem Vista.
- Edição autorizada conserva `vista_payload` bruto. Campos omitidos no PATCH
  mantêm seus valores; vazio enviado explicitamente permite limpar uma data.
- Datas inválidas e saída anterior à entrada são rejeitadas no servidor. Uma
  inconsistência histórica já persistida não bloqueia alteração de outros dados;
  ao editar as datas, o intervalo precisa ser válido.
- Datas registram histórico e não alteram o status, a distribuição ou a carteira.
  Inativação continua passando pelo fluxo de destino da carteira. Não se preenche
  a data de saída com hoje ao sincronizar um status inativo, nem a data de entrada
  com hoje ao cadastrar/importar um usuário.

## Vista

`Vista::CleanImportService` conserva valores anteriores quando DATA/DATA_SAIDA
estão ausentes, vazias, zeradas ou não são datas válidas. Datas válidas de uma
nova importação continuam sendo aplicadas: o dump segue sendo fonte desses
campos. Correções manuais podem, portanto, ser substituídas por uma importação
futura que traga outra data válida. O registro bruto importado continua em
`vista_payload`/`VistaRawRecord`; não há reescrita histórica ou correção automática.

A sincronização `/usuarios/listar` não consulta campos de datas não confirmados
na API e não apaga as datas provenientes do dump ao atualizar nome, telefone ou
status. Teste de sincronização demonstra preservação das duas datas e payload.

## Isolamento, autorização e interface

Gerenciamento segue a permissão de corretores, a hierarquia gerenciável e o tenant
atual. Testes cobrem recusa de outra conta, recusa sem permissão e uso positivo
em outra conta sem integração. Importação com o mesmo `vista_id` em duas contas
não altera o usuário externo à conta corrente.

A interface reutiliza `ax_field_group`, `ax_field_grid`, `ax_date_field` e
`ax_inline_notice`; não cria CSS ou controles próprios. Ritmo revisto pelos
componentes existentes: corpo com gap de 14px, grupo com 6px, grid com 10px e
colunas responsivas do helper. Labels e mensagens em pt-BR, erros junto aos
campos pelo componente compartilhado. Não houve mudança de header, layout ou
comportamento das demais seções.

## Validação local

81 exemplos Rails, 0 falhas: modelo das datas, governança/perfis/system admin,
requests de cadastro/edição/ficha, inativação com transferência de carteira e
importadores Vista. `zeitwerk:check` e `git diff --check` aprovados. Não foi
executada a suíte inteira nem homologação visual em navegador; renderização,
labels, valores e rejeições foram verificados pelos requests. Sem CSS alterado.
