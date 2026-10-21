# Disponibilidade da locação diária — implementação local, 21/10/2026

Escopo confirmado: equipe bloqueia períodos no imóvel; site apresenta calendário
de consulta. Sem reserva automática, pagamentos ou sincronização de calendários
externos. Disponível para todas as contas, sem condicional da Salute.

## Operação

No cadastro de um imóvel de diária, aba Comercial → Calendário de disponibilidade.
Informe data inicial e final para bloquear; ambas são inclusivas. Um bloqueio de
20 a 25 impede outro no dia 25, mas permite um novo a partir de 26. Bloqueio de
um único dia é permitido. “Liberar período” remove o bloqueio inteiro; para
liberação parcial, remova e cadastre os períodos restantes.

O site oferece “Consultar disponibilidade” junto ao preço e um calendário
mensal no detalhe. Indica disponível/indisponível sem nomes, contatos, clientes
ou motivos internos. A consulta está sujeita à confirmação da equipe; sem
bloqueios cadastrados o calendário indica disponível. Não importa reservas
anteriores de Vista, Airbnb, Booking ou Google automaticamente.

## Persistência e proteção

- `habitation_availability_blocks`: conta, imóvel, datas obrigatórias e timestamps.
- Foreign keys, índice do imóvel/período e check de intervalo válido no banco.
- Bloqueios vinculados à conta do imóvel; requisições não aceitam tenant/imóvel
  no corpo. Busca e remoção sempre passam pelo imóvel da conta atual.
- Permissão de edição de imóveis e mesma regra compartilhada de acesso do editor
  (`admin_can_edit_habitation?`), incluindo próprio imóvel/equipe. O endpoint
  público só permite imóvel diário publicamente visível no domínio da conta.
- Sobreposição é conferida na validação e novamente dentro de um lock do imóvel
  durante a gravação. Isso serializa inserções concorrentes antes de existir
  qualquer bloqueio; não depende de um lock sobre uma linha ainda inexistente.
  Escritas SQL externas ao model não possuem essa garantia de sobreposição.
- Mudanças de modalidade preservam os blocos; o calendário deixa de aparecer
  quando o imóvel não é diário. Exclusão do imóvel remove seus blocos.

## Cache, navegação e apresentação

Calendário público tem endpoint próprio, `Cache-Control: no-store`, carregado
por Turbo Frame fora do HTML que pode estar em cache. A resposta refaz a consulta
no mês solicitado. Bloquear/liberar não exige limpar o cache geral das contas.
A tela aberta não faz polling: navegue/recarregue para consultar mudanças novas.

Um único HTML de calendário em `public_theme/components/availability_calendar`,
reutilizado pelo admin. Tabela semântica com caption/dias da semana, estados por
texto e risco no número bloqueado, navegação mensal por links e data atual com
`aria-current`. Sem dependência JavaScript nova. Links do admin atualizam a tela
inteira para manter o calendário e a lista de bloqueios no mesmo mês.

Admin usa painel, campos, ações, heading e header compacto mobile compartilhados;
header respeita a safe-area pelo componente existente. Ritmo do calendário:
padding de 16px (10px no compacto), navegação com gap de 12px, grid mensal com
células de altura mínima visual de 64px e texto que quebra sem overflow.

Temas: Padrão, Salute e Conexão cobertos pelo componente comum e paleta da conta;
Salute Luxury recebe a variante com cores de sua identidade. Temas futuros herdam
o componente; testes percorrem todas as entradas de `Tenant::PUBLIC_SITE_THEMES`.

## Migration e implantação futura

`20261021170000_create_habitation_availability_blocks.rb` foi aplicada, revertida
e reaplicada somente no banco de testes. A migration é necessária antes de
executar a versão nova em outro ambiente. Não houve backfill ou consulta/
alteração em produção. Nenhum deploy foi feito. Rollback estrutural remove os
bloqueios: preservar os dados antes de uma reversão futura que já tenha uso real.

## Validação concluída

- Rodada ampla obrigatória do site: 411 exemplos; 3 falhas preexistentes do
  contrato dark do admin (três painéis de automação, inventário documental e
  `journey_explorer`), já identificadas antes desta demanda. Nenhum desses
  contratos/arquivos foi alterado para mascarar o resultado.
- Rechecagem do escopo: 175 exemplos, 0 falhas, incluindo model do imóvel,
  disponibilidade, admin/escopo de corretor, outra conta, temas públicos e views.
- Build CSS, compilação do CSS administrativo com o componente, Zeitwerk e
  `git diff --check`: aprovados. Migration testada em ida e volta no ambiente test.
- Inspeção no Chrome do HTML real do calendário em larguras de componente de
  760px e 360px. No compacto, mês e navegação se reorganizam e o texto de estado
  permanece acessível enquanto a legenda/riscos evitam colunas apertadas.
- Endpoint com `X-Robots-Tag: noindex, nofollow`, para não indexar/circular
  indefinidamente pelas páginas mensais. Página principal do imóvel mantém SEO.

Não houve homologação em aparelho físico ou teste de carga em produção.
