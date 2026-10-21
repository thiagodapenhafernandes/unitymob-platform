# Imovelweb: recuperação do formato Vista/OpenNavent

## Evidência localizada

O checkout antigo `/Users/thiagodap.fernandes/worksapces/saluteimoveis.com.br`
contém um gerador `Portal::OpenNaventXmlSerializer`, seu teste de referência
`serializes Imovelweb listings using the Vista OpenNavent shape` e a estratégia
`imovelweb => open_navent_xml`. A implementação foi introduzida no commit
`f64577a09aee6c3c8ad792025becb73a4cef8dc4`, de 23/06/2026.

A Unitymob atual selecionava `olx_xml` para o mesmo portal. O gerador antigo
não era a implementação OpenNavent criada/removida em agosto para Casa Mineira:
são códigos distintos. O achado fornece uma referência concreta que não havia
sido consultada na investigação anterior.

Não foi encontrado arquivo de resposta bruto do Vista entre os XMLs/relatórios
consultados no projeto antigo. A fixture nova foi gerada por esse código com
dados fictícios. Não há recibo de carga aceito pelo portal. Portanto a divergência
de contrato está comprovada entre os dois projetos, mas a causa interna da
rejeição do Imovelweb ainda é uma conclusão provável, não confirmação do parser.

## Diferença reproduzida

| Campo | Unitymob anterior | Gerador Salute/Vista recuperado |
|---|---|---|
| Raiz | Carga | OpenNavent |
| Data da carga | ausente | dataModificacao |
| Conta publicadora | ausente nesse bloco | publicador/codigoImobiliaria |
| Referência | CodigoImovel | codigoAnuncio + codigoReferencia |
| Categoria | TipoImovel/SubTipoImovel textuais | tipoPropriedade/idTipo/idSubTipo |
| Preço/operação | PrecoVenda/PrecoLocacao | precos/preco/operacao/quantidade/moeda |
| Publicação | TipoPublicacao literal | publicacao/tipoPublicacao, vocabulário do portal |
| Localização | UF/Cidade/Bairro soltos | localizacao/localidade |
| Fotos | Fotos/Foto/URLArquivo | multimidia/imagens/imagem/urlImagem |

O contrato passa a ser coberto por referência independente do serializador novo.
O formato compacto, os IDs de características e a representação da data foram
mantidos do gerador recuperado. O título vazio do código antigo não foi copiado.

## Correção preparada, não implantada

- Recupera o serializador específico e o conecta somente ao portal `imovelweb`.
- Resolve e-mail pelo tenant, código pelo cadastro da integração e domínio de
  imagens relativas pelo domínio público da conta. Nenhum contato/domínio fixo da
  Salute foi transferido para o código compartilhado.
- Mantém streaming para não voltar a materializar o catálogo inteiro em memória.
- Mantém os filtros de elegibilidade e os tokens/escopos existentes.
- Considera o status de locação e os tipos de negócio permitidos ao escolher preço.
- Preserva tipos de imóveis fora do apartamento com IDs de categoria específicos,
  evitando o fallback inadequado do gerador antigo para terrenos e rurais.
  IDs complementares foram confrontados com a implementação pública UQBITZ 3.4.7
  (https://wordpress.org/plugins/uqbitz-hub-imoveis/).
- Versiona o cache para invalidar ETags do formato anterior.
- Preserva a exigência dos IDs na configuração/readiness.

## Impacto e limites

A mudança é de código compartilhado: após um futuro deploy, TODAS as contas com
portal principal `imovelweb` passam a usar esse formato. Não é uma configuração
exclusiva da Salute. `imovelweb_2`, Casa Mineira, Zap, Viva Real e Chaves na Mão
mantêm suas estratégias atuais. O projeto antigo também diferenciava
`imovelweb` e `imovelweb_2`; não há evidência para trocar a segunda nesta entrega.

Não copiar o arquivo de fixture como carga da conta: contém somente um registro
fictício e uma carga completa pode provocar retirada de anúncios omitidos.

Nenhuma alteração de produção, execução de feed, sincronização, exclusão,
configuração no portal ou deploy faz parte desta preparação.

## Validações executadas

- `rvm 3.2.3 do bundle exec rspec spec/services/portal spec/requests/integrations/portal_feeds_spec.rb spec/requests/admin/portal_integrations_workspace_spec.rb`: 61 exemplos, 0 falhas.
- Inclui fixture recuperada, identidade/domínio de outro tenant, catálogo token-scoped,
  imóvel suspenso/fora do site omitido, operação permitida, opções de publicação,
  categorias residenciais/comerciais/rurais, XML estrito, CDATA, streaming, HEAD/GET,
  invalidação de ETag e formatos vizinhos preservados.
- `rvm 3.2.3 do bundle exec rails zeitwerk:check RAILS_ENV=test`: passou.
- `git diff --check`: passou.
- Não executados: suíte completa, processamento real do importador, deploy.
