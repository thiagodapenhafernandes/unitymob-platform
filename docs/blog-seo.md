# SEO automático do blog

O sistema monta o SEO por tenant, sem exigir preenchimento adicional em cada artigo:

- Título e descrição usam as opções manuais quando presentes; os campos vazios usam título, resumo ou texto do artigo.
- Canonical absoluto usa o domínio público da conta, slug raiz e página correta nos arquivos paginados.
- Home e categorias possuem título/descrição próprios, CollectionPage e ItemList com os artigos visíveis; artigos possuem BlogPosting, autor institucional exibido, datas reais, categorias, imagem e BreadcrumbList.
- Open Graph e Twitter reutilizam esses dados e uma URL estável da capa, sem URLs temporárias do Spaces. Datas de publicação e atualização acompanham o artigo.
- Sitemap inclui somente artigos publicados na data atual e categorias com conteúdo público. Cache varia por artigos e categorias; publicação agendada passa a entrar no escopo sem tarefa manual.
- Resultados de busca interna, arquivos vazios e previews não são indexáveis. Páginas reais de paginação têm canonical próprio e permanecem indexáveis.
- robots.txt permite proxies assinados das imagens públicas, mantendo as demais exclusões. Isso não muda autorização de anexos nem torna o bucket público.
- Conteúdo e links são renderizados no servidor; os rastreadores não precisam executar o editor JavaScript.

## Operação externa

Após deploy, validar o domínio real no Google Rich Results Test e Search Console e no Bing Webmaster Tools, cadastrando /sitemap.xml. Essas ferramentas exigem acesso à conta/propriedade do cliente. Não foram configuradas nem enviadas URLs externamente nesta implementação.

IndexNow é recomendado pelo Bing para avisos de publicação/atualização/exclusão. Não foi ativado: o projeto ainda não possui integração nem chave de verificação por domínio. O sitemap automático já fornece descoberta e atualização; IndexNow pode ser integrado em etapa própria, com fila/retry e verificação dos domínios.

A liberação em robots.txt não substitui eventuais regras de CDN/WAF. Na publicação, verificar Googlebot, Bingbot e OAI-SearchBot na infraestrutura do domínio. Não mudar a política de treinamento do GPTBot para liberar busca: são controles distintos.

Dados técnicos não garantem ranking, indexação, citações por IA nem distribuição em redes sociais. Metadados melhoram os previews quando um link é compartilhado; não publicam posts nas contas sociais. Qualidade factual, autoria e atualização editorial continuam necessárias.

## Referências oficiais consultadas em 09/09/2026

- Google, recursos de IA: https://developers.google.com/search/docs/appearance/ai-features — mesma base de SEO, sem arquivo especial ou schema exclusivo para IA.
- Google, artigos: https://developers.google.com/search/docs/appearance/structured-data/article
- Google, paginação: https://developers.google.com/search/docs/specialty/ecommerce/pagination-and-incremental-page-loading
- Bing, diretrizes: https://www.bing.com/webmasters/help/webmaster-guidelines-30fba23a
- Bing, submissão/IndexNow: https://www.bing.com/webmasters/help/URL-Submission-62f2860b
- Microsoft, métricas de citações por IA: https://blogs.bing.com/webmaster/February-2026/Introducing-AI-Performance-in-Bing-Webmaster-Tools-Public-Preview
- OpenAI, publishers: https://help.openai.com/en/articles/12627856

## Estados e agendamento

O editor e os filtros oferecem Rascunho, Agendado, Publicado e Inativo. Data/hora são interpretadas no fuso configurado do sistema (Brasília).

Agendado exige conteúdo, categoria da conta e uma data futura. A disponibilidade pública é calculada pelo relógio, sem depender de jobs: no instante marcado, o artigo entra no site, na home, nas categorias e no sitemap, e a interface passa a exibir Publicado. O banco pode manter o estado scheduled; consumidores devem usar publicly_visible/publication_status e o filtro with_publication_status, não apenas o enum published.

Alterar a data reagenda; Rascunho ou Inativo cancela a disponibilidade pública sem excluir o conteúdo. Artigos antigos com status published e data futura são tratados como agendados. A migration de rollback converte scheduled para published (preservando a data futura) e inactive para draft.

## Carregamento das imagens (09/09/2026)

O helper do blog gera diretamente a rota assinada de proxy do Active Storage. Não consulta a existência de cada objeto no Spaces durante a renderização do HTML. Versões ausentes são geradas pelo endpoint da imagem, quando solicitadas; imagens internas mantêm loading=lazy e decoding=async. A capa é eager/high, com srcset de 640/1600 e sizes para o espaço ocupado. Novas capas têm essas duas versões pré-processadas pela fila nativa do Active Storage.

Validação Chromium desktop, viewport 1365x900, sem limitação artificial de rede, contexto novo em cada URL:
- Produção antes: categoria Praias LCP 3,36 s; artigo Férias LCP 3,44 s.
- Local depois, variantes já geradas: categoria LCP 2,85 s; artigo LCP 1,84 s.
- A primeira geração da variante pequena no ambiente local levou o LCP da categoria a 3,97 s. O pré-processamento de novas capas reduz esse risco, mas depende da fila.
Esses números são amostras de ambientes diferentes, não um ganho percentual comprovado em produção nem garantia para qualquer conexão.

Na publicação, gerar as duas variantes de capas existentes com o serviço do tenant registrado, validar todas as URLs públicas e medir novamente LCP com cache frio de navegador e quente de imagens. Não limpar variantes existentes. A meta em produção ainda depende desse deploy e da medição posterior.
