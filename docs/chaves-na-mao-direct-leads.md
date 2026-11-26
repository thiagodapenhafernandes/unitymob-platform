# Chaves na Mão — recebimento direto de leads

Implementação local conforme o contrato imobiliário enviado pelo atendimento em
25/11/2026. Requer a migration `20261126160000`, Rails e worker Solid Queue.
Não exige mudanças no Gateway. Não houve ativação de contas nem teste real com o
fornecedor nesta implementação.

O fluxo é **Chaves na Mão → webhook Unitymob → filas da conta**. Não há C2S
intermediando nem credenciais/conexão C2S necessárias para esta integração.

## Configuração por conta

Em Portais → Chaves na Mão → Recebimento direto, salvar ID da conta anunciante,
e-mail de acesso e Token Integração de leads da imobiliária. O token fica em
Meus Dados → Dados Adicionais no dashboard do Chaves na Mão. O token é criptografado
e não volta no formulário. Não usar a senha de acesso ao portal.

- Habilitar recebimento: permite autenticar e guardar eventos.
- Criar leads e aplicar as regras desta conta: ativa o processamento operacional.
  Desmarcado, mantém apenas captura para homologação.
- As opções são independentes por tenant; a criação operacional começa desligada.
  Eventos antigos de captura não são reproduzidos automaticamente.
- Conexões antigas precisam receber o e-mail de acesso para usar a autenticação
  oficial. Os formatos provisórios `Basic <token>` e `Bearer <token>` foram retirados.

Encaminhar ao portal a URL da própria conexão:
`POST /webhooks/chaves_na_mao/:route_key`, usando HTTPS em produção.
O portal envia `Authorization: Basic <base64(email:token)>` e JSON. URL autenticada,
e-mail e token determinam a conta; campos do corpo nunca selecionam outro tenant.
Conta inativa ou recebimento desligado retorna 409; rota desconhecida, 404;
credencial inválida, 401; corpo acima de 64 KiB, 413; JSON inválido, 400;
objeto vazio/não objeto ou ID operacional ausente/inválido, 422.
O limite existente é 120 pedidos por minuto/IP.

## Processamento

O endpoint persiste o recibo criptografado e enfileira somente seu ID, respondendo
200 sem esperar distribuição ou notificações. Reentregas operacionais usam o ID
estável do lead do fornecedor, único por conexão, mesmo que `sendAt` ou a ordem
dos campos mudem. Jobs concorrentes travam o recibo; processado/quarentenado não
é executado novamente. Falhas transitórias têm cinco tentativas no ActiveJob;
pendências esgotadas ficam no monitor de jobs. Reenvio do portal de um recibo ainda
pendente também permite enfileirar novamente.

`ChavesNaMao::ReceiveLead` aceita `segment=REALTY` e usa `Leads::Intake` para criar
ou complementar o contato. O ID de ingresso é `chaves_na_mao:<route_key>:<id>`.
Repetição não cria outra consulta, redistribui ou notifica novamente. Nova consulta
do mesmo contato segue matching, fidelização e distribuição já definidos na conta.

- Nome, e-mail, telefone e mensagem vêm da raiz do JSON. Contato sem telefone é
  aceito somente com e-mail válido; sem contato utilizável fica em quarentena.
- Imóvel é buscado exclusivamente em `tenant.habitations.codigo` por `ad.reference`,
  a mesma referência enviada pelo XML. Não usar `ad.id` como ID interno.
- Referência ausente/desconhecida mantém lead sem vínculo, preservando referência,
  anúncio e mensagem para conferência. Referência ambígua fica em quarentena.
- `Venda`, `Locação` e `Venda/Locação` conservam as modalidades venda, locação e ambos.
  Locação de imóvel da conta configurado como diária usa diária. A finalidade mista
  não prova uma preferência exclusiva do interessado.
- A origem direta corresponde a filas com fonte Portais; não cai em Site por falta
  de reconhecimento da origem. Regras, funis, horários, elegibilidade, represamento,
  contingência, notificações e destino da fila continuam os configurados na conta.
- Eventos inválidos ficam `quarantined` com motivo seguro, sem expor payload no log.
  A tela mostra os dez eventos recentes e seu estado. O timestamp da conexão só é
  atualizado após processamento bem-sucedido.

## Homologação e virada

A documentação informa timeout de 30 segundos, recomenda resposta em menos de cinco,
e anuncia três reenvios em 15s, 5min e 1h. Apenas leads novos após ativação são enviados.
Combinar teste, reenvio e virada do destino com o atendimento.

Clientes em migração mantêm suas configurações e cadastros existentes. A entrada
direta pode complementar um contato migrado sem apagar seu histórico. Se a conta
mantiver temporariamente outro canal entregando os mesmos contatos, o contrato
não fornece um ID para correlacionar essas duas entregas: combinar a transição
cadenciada com a conta, sem descartar consultas distintas apenas pelo telefone.
Nenhuma configuração de migração, XML, e-mail de propostas ou fila é alterada
automaticamente pelo conector.

Para a parceria, o atendimento solicita nome, site e logo da Unitymob; WhatsApp,
telefone e e-mail técnico; horários de atualização do XML; instruções para obter
XML e URL de leads na interface; e as URLs de cada cliente em comum. Também permite
que a Unitymob centralize o envio das URLs mediante aviso. Nenhum dado foi enviado
ao atendimento por esta implementação.

Fontes oficiais:
- https://chavesnamao.github.io/lead-documentation/api/autenticacao.html
- https://chavesnamao.github.io/lead-documentation/api/imoveis.html
- https://chavesnamao.github.io/lead-documentation/recursos/faq.html
- https://chavesnamao.github.io/xml-documentation/
