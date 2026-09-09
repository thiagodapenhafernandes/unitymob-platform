# Blog por conta

O menu **Blog**, na área de Site Público, exige a permissão de gerenciamento de marketing. Artigos, categorias, filtros, previews e uploads usam a conta atual. A identidade visual pública vem das configurações existentes da conta.

## Publicação

- Home: `/blog`; categoria: `/blog/categoria/:slug`; artigo: `/:slug`.
- O domínio resolve o tenant pelo mecanismo existente do site público.
- Rascunhos e artigos com data futura não aparecem publicamente nem no sitemap.
- O slug é exclusivo dentro da conta e não pode ocupar uma rota do sistema, landing page ou redirecionamento ativo.
- O editor usa Action Text/Trix. Categorias podem ser criadas e selecionadas na coluna direita.

## Arquivos

Imagens (JPEG, PNG, WebP e GIF) e PDFs de até 20 MB passam pelo endpoint autenticado de uploads. O servidor verifica formato, propriedade e serviço antes de aceitar o anexo; referências a blobs de outra conta ou de outro módulo são rejeitadas.

Em produção, a conta precisa ter DigitalOcean Spaces configurado. O módulo não faz fallback para armazenamento local. Desenvolvimento usa o bucket sandbox existente; testes usam o serviço de testes. Os arquivos continuam privados, acessados por URLs assinadas do Active Storage. O HTML em cache usa URLs de proxy estáveis, paginação e imagens com carregamento tardio.

## Importar WordPress

A migration `20260909190000_create_blog.rb` deve estar aplicada. Execute primeiro a simulação no ambiente desejado, informando explicitamente a conta e o JSON:

```sh
TENANT_SLUG=conexao-imobiliaria BACKUP=/caminho/blog-conexao/artigos.json rvm 3.2.3 do bundle exec rails blog:import_wordpress
```

Para gravar, repita com `EXECUTE=1`. Os arquivos locais referenciados precisam estar junto ao backup. O importador preserva slugs, datas e conteúdo, troca imagens por anexos no Spaces e ignora artigos já importados pelo ID WordPress. Uploads são reutilizados em retries; uma falha não publica um artigo parcialmente salvo. O backup não é modificado.

Na validação local da Conexão foram importados 13 artigos e 89 arquivos únicos referenciados. Nenhuma importação foi executada em produção. O domínio local cadastrado é `conexaobc.com`; confirmar o domínio definitivo antes de publicar, pois a solicitação menciona `conexaobc.com.br`.

## Verificação

```sh
rvm 3.2.3 do bundle exec rspec spec/models/blog_article_spec.rb spec/requests/blog_spec.rb spec/requests/landing_pages_spec.rb spec/services/blog/wordpress_importer_spec.rb spec/helpers/blog_helper_spec.rb
rvm 3.2.3 do bundle exec rails zeitwerk:check
rvm 3.2.3 do bundle exec rails tailwindcss:build
```

Os testes cobrem isolamento por domínio/conta, permissões, publicação, categorias, propriedade dos uploads, conflito com landing pages e importação repetida. A suíte existente `spec/services/seo/sitemap_builder_spec.rb` apresenta uma falha em URL de empreendimento também reproduzida com sua implementação anterior; o teste de sitemap do blog passa.
