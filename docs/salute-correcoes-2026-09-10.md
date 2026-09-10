# Salute — acompanhamento das correções

**Data:** 10/09/2026

**Situação:** pacote implementado e validado para publicação em Salute e Conexão.

**Diretriz:** corrigir as regras compartilhadas do sistema; os códigos informados servem como exemplos e para conferir os registros antigos.

## Escopo por demanda

| Item | Entendimento e encaminhamento |
| --- | --- |
| 1 — Dois captadores | Exibição dos nomes completos no card, com quebra de linha para não esconder o segundo nome. |
| 2 — Organização, classificação e download das fotos | O botão volta a funcionar após cada organização, inclusive após falha. A classificação salva ao mudar a seleção, respeitando a permissão do perfil. Downloads usam código do imóvel e sequência, preservando a extensão. |
| 3 — Cadastros por tipo | Características e infraestrutura distinguem galpões, salas comerciais e terrenos. Campos de terreno deixam de aparecer vazios em apartamentos/salas; valores já preenchidos continuam acessíveis. Características personalizadas e seleções existentes são preservadas. |
| 4 — Desativar usuário dentro do cadastro | A opção interna abre o mesmo fluxo de transferência ou desvinculação de imóveis e leads usado na listagem. A desativação é concluída por esse fluxo. |
| 5 — Marca-d’água no DWV | Novas importações processam as fotos quando a conta tem marca configurada. O processamento preserva ambiente e visibilidade e evita duplicação nas tentativas seguintes. Imóveis antigos precisam entrar no reprocessamento descrito abaixo. |
| 6 — Rua, mapa e Street View | Confirmada ausência de coordenadas nos exemplos 9560 e 9569 em produção. Implementado preenchimento em segundo plano para endereços sem coordenadas, usando a integração Google configurada na conta. A exibição continua respeitando as opções de localização exata, aproximada ou oculta. |
| 7 e 21 — Permuta indevida, 8988 e 9622 | “Aceita Permuta” estava em características antigas. Esse texto deixa de aparecer como diferencial/infraestrutura. Editar outras características também não reativa uma permuta explicitamente desmarcada. |
| 8 — Ano nas datas | Cadastro e atualização passam a mostrar dia, mês, ano e horário na ficha do imóvel. |
| 9 — BI de venda e publicação | Aguardando definição do cliente. Fora desta implementação. |
| 10 — Vista, 8080 e 7829 | Não encontrados no cadastro atual. A consulta ao Vista retorna apenas o bloco de fotos, sem os dados cadastrais. A sincronização agora recusa essa resposta incompleta, evitando criar imóveis vazios. A recuperação desses dois imóveis depende de uma origem com dados completos. |
| 11 — Ordem alfabética | Características e infraestrutura ordenadas alfabeticamente, de cima para baixo em cada coluna. |
| 12 — Publicar ou salvar interno no cadastro novo | Cadastro direto apresenta as duas ações; a escolha é respeitada ao salvar. Perfis sem permissão para publicar continuam restritos ao salvamento interno. |
| 13 — Acesso ao módulo de proprietários | A restrição da função horizontal passa a ser aplicada também no servidor, mesmo quando essa função está vinculada ao perfil de administrador. Acesso pelas telas e URLs do módulo obedece à permissão. |
| 14 — Filtro de captador | Lista corretores e pessoas que possuem captação vinculada; administradores sem captação deixam de aparecer. |
| 15 — Contato do proprietário, 6029 | Encontrado telefone em “FonePrincipal” no Vista, campo que não era consultado nessa sincronização. Corrigida a leitura e a preservação do contato legado ao salvar o mesmo proprietário. A troca de proprietário continua removendo dados da pessoa anterior. Recuperação do registro antigo preparada separadamente. |
| 16 — Excluir características | Corrigido o tratamento do modal compartilhado, para apenas o gerenciador que abriu a categoria executar a ação. |
| 17 — Filtro padrão ativo | Sem seleção explícita de status, a consulta usa Venda, Aluguel e Diária. A opção “Todos” continua permitindo consultar os demais status. |
| 18 — Configuração padrão da rua | O sistema já possui configuração de localização exata/aproximada/oculta e Street View. Confirmado que a Salute usa localização aproximada; esse modo suprime o Street View herdado. Não foi criada uma configuração duplicada nem alterada a exposição de endereços em massa. |
| 19 — BI de agosto | Aguardando definição do cliente. Fora desta implementação. |
| 20 — DDD/DDI 55 | Ajustada a identificação pelo tamanho do número, preservando o DDD 55 e distinguindo o prefixo internacional. |
| 22 — Fotos do empreendimento, 6686 | O vínculo com o empreendimento passa a incluir suas fotos automaticamente, sem depender do antigo botão de ativação. O exemplo 6686 já reúne 22 fotos próprias e 12 do empreendimento na base consultada, mas está vendido a terceiros; esse status foi preservado. |
| 23-A — Edição do 7199 | Corrigido o bloqueio do próprio captador por diferença entre sua área de atuação e a finalidade do imóvel. O acesso da gestora depende dos vínculos de gestão; esses vínculos não foram alterados, conforme a exclusão do item 25. |
| 23-B — E-mail marketing | Aguardando definição do cliente. Fora desta implementação. |
| 24 — URLs, exemplo 9198 | O código automático é definido antes da geração da URL. URLs antigas sem código são corrigidas ao salvar, com preservação de histórico para manter os links anteriores. Foi preparado procedimento para corrigir os registros existentes. |
| 25 — Gestores de venda e locação | Excluído expressamente. A definição de gestores será tratada por outro caminho. |

## Complemento — infraestrutura do empreendimento no administrativo

Ao vincular uma unidade a um empreendimento, o cadastro administrativo marca a infraestrutura e o lazer do empreendimento, somando às seleções existentes. O salvamento aplica a mesma regra; edições posteriores da unidade são preservadas. O formulário também apresenta opções personalizadas do empreendimento, respeitando o escopo da conta.

## Três definições que permanecem com o cliente

1. **Item 9:** qual indicador do BI deve separar imóveis publicados e internos, e se a publicação considerada é a atual ou a existente na data da venda.
2. **Item 19:** ano de referência de agosto, indicadores divergentes e valores esperados para comparação.
3. **Item 23-B:** ferramenta de e-mail marketing e fluxo pretendido para os contatos e campanhas.

## Complementos necessários na publicação

Estes pontos são de aplicação das correções e recuperação de dados, não novas dúvidas de produto:

- **Classificação de fotos:** o perfil Corretor da Salute tem `foto_classificacao` explicitamente bloqueado. Liberar esse campo na configuração do perfil para que os corretores usem a classificação; manter os demais bloqueios.
- **Mapa:** selecionar localização exata e Street View na configuração da conta caso a decisão seja expor a rua por padrão. Restrições específicas de cada imóvel continuam prevalecendo. Recuperar coordenadas dos imóveis antigos selecionados. A disponibilidade das imagens do Street View depende do Google.
- **DWV:** selecionar o histórico que deve receber marca-d’água. A importação futura já agenda o processamento; não foi disparado um reprocessamento geral.
- **6029:** aplicar a recuperação somente dos contatos vazios, conferindo que o código do proprietário na origem corresponde ao proprietário vinculado.
- **URLs antigas:** executar o reparo dos registros selecionados após publicar o suporte ao histórico. A migração inclui os links atuais no histórico antes de qualquer renomeação.
- **8080 e 7829:** a resposta atual do Vista não permite recompor os imóveis. É necessária uma exportação ou acesso da origem que contenha os cadastros completos.

## Procedimento técnico para registros antigos

Arquivo: `script/maintenance/repair_property_catalog.rb`.

Exige conta, códigos e operações explícitos. O padrão é simular, sem gravar nem agendar jobs. Operações disponíveis: `slugs`, `maps`, `dwv_photos` e `owner_contacts`. Não altera status comercial nem substitui contatos já preenchidos. A recuperação de contatos exige correspondência do código do proprietário na origem.

Exemplos de simulação, no ambiente que será conferido:

```sh
TENANT_ID=1 CODES=9198,9569 OPERATIONS=slugs bundle exec rails runner script/maintenance/repair_property_catalog.rb
TENANT_ID=1 CODES=9560,9569 OPERATIONS=maps bundle exec rails runner script/maintenance/repair_property_catalog.rb
TENANT_ID=1 CODES=6029 OPERATIONS=owner_contacts bundle exec rails runner script/maintenance/repair_property_catalog.rb
```

Depois de revisar o resultado e publicar o código, `EXECUTE=1` aplica exclusivamente o escopo informado. Para DWV, informar os códigos escolhidos e `OPERATIONS=dwv_photos`; é necessário ter marca configurada e fila de mídia funcionando.

**Produção consultada:** Salute, tenant 1, release 622, revisão `05141649279c08bcf29f4547fb475a5bec567ede`. As conclusões dos exemplos foram obtidas nessa base e no Vista; a cópia local tem dados anteriores e não contém 9560 e 9569. Não houve deploy nem execução de reparo dos dados de produção nesta etapa.

## Validação

- Rodada final para publicação: **210 testes Rails e 5 testes JavaScript passaram**. Testes de requisição, modelo, serviço e jobs cobrem os fluxos alterados, permissões, isolamento por conta, preservação de contatos e repetição do processamento.
- Conferência visual local confirmou os botões de publicação, ordenação vertical em colunas e abertura do gerenciador de características.
- Compilação CSS e carregamento de classes Rails (`zeitwerk:check`) concluídos com sucesso.
- A rodada ampla inicial executou 329 exemplos: uma expectativa de “Captador +1” foi atualizada para os dois nomes; a outra falha, relativa à identificação de imóveis DWV no card, já existia. Também foram reproduzidas no código anterior três expectativas antigas de títulos e duas de governança de perfis. Esses seis problemas preexistentes não foram tratados como parte deste pacote.
