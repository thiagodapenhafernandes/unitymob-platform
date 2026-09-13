# Meta — correção de roteamento e evidências

## Publicação

Gateway publicado na revisão `a242b9eb3b01ea3da5c86a6dde0a910bb53ce26c` em 13/09/2026. CRM permanece na revisão `bd7cf47b`; configuração da Salute alterada para `META_LEADS_WEBHOOK_MODE=gateway`, com reinício de Puma e Solid Queue.

O usuário confirmou destino exclusivo da página `103563744715606` em `https://saluteimoveis.com.br/webhooks/meta`. Foram transferidas 990 rotas, preservando seus estados: 970 ativas e 20 inativas. O registro antigo da conta 72 no servidor Conexão não foi encontrado ao executar a desativação (zero alterações); o usuário informou que estava removendo a conexão acidental.

## Correções

- Registro de página/formulário recusa outro cliente ou URL de destino com HTTP 409. Lock transacional por página protege registros concorrentes.
- Cada entrega Meta contém somente seu evento, incluindo lotes com páginas diferentes.
- Encaminhamento valida correspondência entre página e rota e isola também payloads antigos usados por retry.

## Provas executadas

- 31 exemplos passaram: `DATABASE_URL=postgres://localhost/unitymob_whatsapp_gateway_test rvm 3.2.3 do bundle exec rspec spec/meta_isolation_spec.rb spec/app_spec.rb spec/services`, em `gateway/`.
- Teste com duas páginas comprova um evento por destino e HMAC correspondente; retry de lote antigo não envia o outro evento; rota incompatível é bloqueada.
- Na aplicação publicada, tentativa de sobrescrever a rota Salute por outro cliente/URL retornou **409**, sem alterar o registro.
- Gateway → Salute com payload vazio e assinatura correta: **200**. Assinatura incorreta: **403**. Nenhum lead é criado por esse payload.
- Auditoria das rotas Meta ativas: 970 para Salute, 157 para Conexão, nenhuma página com múltiplas URLs de destino.
- Salute em modo gateway com configuração completa; gateway em execução, zero reinícios após publicação; saúde pública **200**.

## Limites

Não foram reprocessados eventos reais nem simulados novos contatos. As provas validam isolamento, resolução das rotas e autenticação HTTP; não substituem a confirmação de uma nova conversão real criada pela Meta.

O Instagram da Salute estava desativado. A consulta do aplicativo mostrou inscrição de `page/leadgen` no gateway, mas não inscrição do objeto Instagram. Portanto, esta correção não declara Direct operacional.

Backups protegidos: `/opt/unitymob-gateway-before-a242b9eb.tgz` e `/opt/salute-routes-before-a242b9eb.json` no gateway; `.env.before-meta-gateway-a242b9eb` no diretório shared da Salute. Não copiar seus conteúdos para documentação ou logs.


## Complemento local — seleção independente por integração

Implementado após a constatação de que o mesmo login/app Meta é usado nas duas empresas. Esta etapa ainda não foi publicada nos CRMs.

- Cada integração guarda suas páginas selecionadas; reconectar o Facebook preserva essa seleção.
- A descoberta lista páginas disponíveis, mas não ativa automaticamente novas páginas. Remover uma seleção desativa o recebimento e o Instagram local imediatamente.
- A consulta padrão de anúncios usa apenas negócios das páginas selecionadas. A consulta ampliada fica disponível somente durante impersonação.
- Falta de autorização não apaga a seleção; o motivo permanece salvo. Falha na confirmação do destino pelo gateway impede a ativação e mantém uma pendência.
- A reconciliação de formulários observados consulta a página no tenant da regra, sem aproveitar registros de outra conta.
- A migração preserva as páginas anteriormente ativas. As seleções antigas devem ser conferidas em cada CRM; não se infere a empresa pelo nome da página.

Validação local: 40 exemplos passaram, incluindo reconexão, isolamento da seleção e dos negócios consultados, desativação e falhas persistentes. `zeitwerk:check` passou. Nenhuma conversão real da Meta foi gerada nesta etapa.

Na autorização da Meta, manter os ativos das duas empresas autorizados; selecionar os destinos separadamente em “Páginas desta conta” de cada CRM. O CRM não consegue restaurar uma permissão removida no painel da Meta.


## Complemento local — Direct automático e apresentação dos recursos

A sincronização agora descobre e prepara automaticamente o Direct nas páginas selecionadas. A conexão OAuth agenda essa preparação em segundo plano. Não há mais botões separados para descobrir o perfil ou ativar o recebimento na interface.

A ativação exige página selecionada e ativa, inscrição Instagram/messages do aplicativo no callback esperado, rota do gateway confirmada quando aplicável e inscrição de mensagens da página confirmada pela Meta. Falhas desativam o recebimento e persistem o motivo e a data da verificação por página. A inscrição de formulários é preservada.

A tela prioriza páginas e recursos; permissões e configuração técnica ficam recolhidas. Em modo gateway, não apresenta campos de configuração manual. O Direct mostra estado confirmado, ausência de perfil ou pendência. “Pronto para receber” indica configuração confirmada; a primeira mensagem real continua sendo necessária para comprovar entrega completa.

Validação desta etapa: 43 exemplos passaram; build CSS e `zeitwerk:check` concluídos. Conferência visual com HTML renderizado pelos testes e CSS local em desktop e mobile; viewport e largura de conteúdo de 390 px, sem transbordamento horizontal. As consultas externas estavam simuladas nos testes. Este complemento ainda não foi publicado nem declara o Instagram de produção operacional.


## Complemento local — catálogo restrito à impersonação

O bloco “Páginas desta conta” e a assinatura do canal que atualiza seu catálogo aparecem somente na sessão impersonada. O servidor recusa alterações da seleção e consultas ampliadas de anúncios fora dessa sessão. O catálogo deixou de ser transmitido pelo canal comum, e o progresso da descoberta não informa nomes de páginas externas.

Usuários comuns continuam consultando os recursos das páginas selecionadas; os endpoints de formulários também exigem essa seleção. O salvamento de anúncios valida o escopo das páginas selecionadas fora da impersonação.

Validação: 37 testes de requisição e job passaram, incluindo sessão real de impersonação, ausência do catálogo e de sua assinatura para o usuário comum, bloqueios 403/404, preservação da seleção e envio privado da atualização. Alterações locais, sem deploy.

A restrição não corrige vínculos antigos incorretos. Páginas já selecionadas precisam ser revisadas pelo suporte; não foi feita remoção automática por nome.

## Complemento local — seleção nas regras de distribuição

As opções e os nomes apresentados nas regras agora exigem página ativa, selecionada na própria integração e pertencente ao tenant da regra. A mesma consulta delimita os formulários automáticos e a reconciliação de formulários observados.

O salvamento administrativo recusa páginas e formulários fora desse escopo. A distribuição automática também recusa origens identificadas por página ou formulário desmarcado, mesmo que a regra antiga ainda guarde esses IDs. O histórico não foi apagado e regras sem identificação Meta mantêm seu comportamento anterior.

Validação: 97 exemplos passaram nas suítes de regras, distribuição, integração e sincronização. Após cobrir também leads identificados somente por formulário, os 36 exemplos do serviço de distribuição passaram novamente. Incluídos casos de página não selecionada ainda ativa, ocultação de nomes antigos, rejeição de requisição direta e interrupção da inclusão automática após desmarcar. Sem deploy ou alteração de dados de produção.
