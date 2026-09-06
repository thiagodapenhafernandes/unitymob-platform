# Publicação Discovery / extensão 0.4.0 — revisão

Preparação em 06/09/2026. Nenhuma alteração em produção executada.

Base atual e remota: `a5b12308952d40bf68b22a47e666040374924b41`.
Branch local: `codex/whatsapp-extension`, pacote ainda sem commit.

## Alvos confirmados ao vivo

- Gateway: root@webhooks.unitymob.com.br, /opt/unitymob-whatsapp-gateway; container ativo. Preservar compose.yml exclusivo do servidor, .env, logs e tmp no rsync. Imagem anterior: sha256:50b222c56d86e51c1dcce1ac98943ee101baaada2dafe23b2f7b2bb2fdd53594.
- Salute: salute@143.110.138.67, /home/salute/deploy; release 578; tenant 1, https://saluteimoveis.com.br. Tenant 2 é QA e fica excluído da ativação.
- Conexão: conexao@app.conexaobc.com, /home/conexao/deploy; release 168; tenant 72, https://app.conexaobc.com.
- Ambos os CRMs estão na revisão base acima, Puma/Solid Queue ativos e ainda sem a API da extensão.

## Pacote

Gateway Discovery V2 com Resend HTTPS, diretório de vínculos isolado por instalação/tenant/usuário, três novas tabelas no Gateway; API/autenticação/termos e ações da extensão nos CRMs, com três migrations aditivas; extensão 0.4.0 e documentação. Segredos excluídos.

Ficam fora: correção de filtros ao excluir lead, arquivos mobile, outras worktrees, Central e instalação/publicação nativa. O mobile legado permanece; a versão V2 móvel terá publicação separada. A rota legada retorna 409 para identidade com múltiplas contas V2, conforme documento de ativação.

## Execução após aprovação deste pacote

1. Commit seletivo dos arquivos abaixo; promoção para develop/master sem incluir WIP externo, push sem força. Registrar revisão final antes da publicação.
2. Backup do banco e .env do Gateway e captura da imagem atual. Gerar credenciais exclusivas para Salute e Conexão e segredo independente. Configurar RESEND_API_KEY em arquivo privado, remetente acesso@unitymob.com.br, origens/tenants acima. Nunca imprimir segredos.
3. Empacotar gateway/ pelo git archive da revisão publicada; revisar rsync com -n, preservando compose.yml e .env. Aplicar rsync; no Gateway: `docker compose build whatsapp-gateway`, `docker compose run --rm whatsapp-gateway bundle exec rake db:migrate`, `docker compose up -d whatsapp-gateway`. Agendar discovery:cleanup por hora.
4. Backup/configuração privada dos CRMs: DISCOVERY_INSTANCE_ID/TOKEN/GATEWAY_URL, BROWSER_EXTENSION_TENANT_IDS por instalação e BROWSER_EXTENSION_ALLOWED_IDS=hokkkaibgfilkmgaohfblcigmhlppdhl. Resend permanece apenas no Gateway.
5. Na raiz: `rvm 3.2.3 do bundle exec mina all deploy` (somente Salute e Conexão).
6. Reconciliar vínculos por tenant: dry-run e depois `RAILS_ENV=production TENANT_ID=1 EXECUTE=1 bundle exec rake discovery:reconcile` na Salute; equivalente TENANT_ID=72 na Conexão. Validar contagens, fila e isolamento, sem exibir dados pessoais.
7. Verificar revisões, serviços, migrations, /up e rotas de login/API. Atualizar extensão local para dist-discovery; validar código e seleção com participação do usuário no login/2FA, sem criar ou alterar leads reais.

## Validação

37 testes CRM, 42 Gateway, 41 extensão: todos passaram nesta preparação. Dry-run de rsync concluído; nenhum arquivo removido e compose.yml protegido. Entrega Resend já confirmada em Gmail no teste anterior. Login humano/2FA completo permanece dependente da sessão do usuário após publicação.

## Manifesto do pacote (antes do commit)

| Arquivo | SHA-256 |
| --- | --- |
| `app/assets/stylesheets/admin/components/form_control.css` | `7aa3c384f7b3b6206e3e10f09f3b31bcfe6ba11b79cce6a36487601a62cb08ec` |
| `app/assets/stylesheets/admin/components/operational_panel.css` | `d988552e0b54583f072d6e4219133970fe50004b6a1c9b5806d0948a370fcb86` |
| `app/controllers/admin/browser_extension_connections_controller.rb` | `ae4173345e1dd00ab30581d52dc1fb216d619622ef10ac822538a04de2621e0d` |
| `app/controllers/admin/sessions_controller.rb` | `5823366863673501adc5879ff80e8be7d7703e49baccc6e3bd310fdc2465b112` |
| `app/controllers/api/v1/browser_extension/base_controller.rb` | `2887f551f3e3341224b1d31d33d44c8628c61f4d46e653babd995c49744b3917` |
| `app/controllers/api/v1/browser_extension/leads_controller.rb` | `4185baab21046ccea6f2a64fcd140559f9acf12711f268228098ed3ddda7f20b` |
| `app/controllers/api/v1/browser_extension/operations_controller.rb` | `f55cf71fdb1eea215d13edd2b2d4f60f4717f56e6e9b644f73628fbf59624af2` |
| `app/controllers/api/v1/browser_extension/sessions_controller.rb` | `46df700c812599e423d3185c92b58b6d3729f6bc10e62ed21e9f5ebe44df8831` |
| `app/javascript/controllers/browser_extension_login_controller.js` | `552fafb864306f04778a32a67819864a8423177bf5454de428f9749d7e7ffe3a` |
| `app/jobs/mobile/sync_account_membership_job.rb` | `b9144bf303929fc8cdc59c4c05dc512d12330fb695f4bd08450deeace573731a` |
| `app/models/account_membership.rb` | `422eeca9fe8216c6e7f3187cbc4be20bccad14afc0db84cf7055e7aca4af84b9` |
| `app/models/admin_user.rb` | `40d96c1cd11e9621819cf675403e1f5c6be153267e6ce74e4a26b86fff62212a` |
| `app/models/browser_extension_grant.rb` | `d9c51dc4ba144ae7701830ed274371d99c0b93879e50498c99b580e2d59ea263` |
| `app/models/browser_extension_operation.rb` | `a33df35afa22b8173cca2be18227213fc623a00028aa15360e5b2d080b690f09` |
| `app/models/trusted_device.rb` | `29b67e14f4d7abb339b90591769e6880c22bace5aa81f3b14e6674ce80f4c954` |
| `app/services/access_control/policy.rb` | `f29d76e57aeb868adcf473c3459a5e13b7ff8bd16c3b4c4de8c75b3a23ca50c3` |
| `app/services/admin_users/hard_deleter.rb` | `a862892a8d43b3b53bab3d4736be495a09b0c761a0a559e14eb07df737b9b56d` |
| `app/services/mobile/account_membership_registrar.rb` | `eb3956dacaeefb1f88f5115f43cb86b6eea748c98bf0e81a65793c2e8cd1d3b2` |
| `app/views/admin/browser_extension_connections/index.html.erb` | `59106e8cf08a70c7fd75ec414d343adf83dce0777ad65b794b6f0f859eb65da8` |
| `app/views/admin/browser_extension_connections/new.html.erb` | `5d74c086dcf539f21cc356dc3df40eb4dfd4d93b4fdccd6399b32259fb96f2bf` |
| `app/views/admin/leads/show.html.erb` | `c9fa5266d7245ba8d16f4ebee39cac0ac452d36a6a52b7500689f19d72a3c352` |
| `browser-extension/.gitignore` | `ac6c22291670ab8658475799e5cc2952ecd138d7b10e2d7d52c858b909105d5a` |
| `browser-extension/README.md` | `77ba1a818542ffeda86dff8815c6ac0ac69c81c5aed3e92183be6c556a13961a` |
| `browser-extension/icons/icon-128.png` | `70a7bcb30f9d3f71685f581af1ff882a508c1e9a9507610ec646b0e5b223b9ac` |
| `browser-extension/icons/icon-16.png` | `1986a06315b5940e8a5f6cc2184e2c25e61cb79546a9743fd8390c7ec2d51301` |
| `browser-extension/icons/icon-32.png` | `b64670fda9d78e1a99bc3716fdd1bbaff0745b076cef159d57d57fb7c6d631fa` |
| `browser-extension/icons/icon-48.png` | `d28875d705e4dd42ae9ae2ab18df5b7d006e1796b020ef5242fe1fca45bf471b` |
| `browser-extension/package-lock.json` | `2ce042f411a31a13df99e0ac4c113bf8ffe3bcdde5643e40fac198f3608f1ffa` |
| `browser-extension/package.json` | `8916ec9c7da7b5f863550ebef8a843f38b838f751091940ae3eb93e3813cfcb7` |
| `browser-extension/public-key.txt` | `a41737d4fb2ebd339e682709d9ff70284f885f2faf39311ef1ade2104ca49341` |
| `browser-extension/scripts/build.js` | `07ab9c88229e7c05144417f6bf85deb60e7ba0235013c0be568b6b2e6b54618f` |
| `browser-extension/src/background.js` | `bbdb609d744745941120bb476dada830ed8fc166c0798bdd5078e2a02a3db17e` |
| `browser-extension/src/config.js` | `9d136f04cc3cd686e840d4500aba25a844e5739ec14eb3becd39039e6d58301c` |
| `browser-extension/src/context.js` | `1ff11acf31f6a6bc9dc0668c31d07b12e2cd2065e8022fad1d28004a4823d5b9` |
| `browser-extension/src/launcher.js` | `904323da520e87a0365985500eef7b120a5631debe6b6c883e2f8948638b91b4` |
| `browser-extension/src/panel.css` | `8fb56910b01e35deaf6413f4df89b200ceb3f446036bd685c5d71b79eb426156` |
| `browser-extension/src/panel.html` | `9275db6a18b4066c18827d710dd6c30a19d3f7857ab01c8cc66dc75a45a27622` |
| `browser-extension/src/panel.js` | `1b85a6efe9d05f3d0255457c85a1516de1d843d6845d86ce03ba74a170b8315a` |
| `browser-extension/src/security.js` | `739156a164df3b262c0111603a6726fc90abe4d251cb000819087089e9d946f3` |
| `browser-extension/test/background.test.js` | `259b9fb1b091837d6cadfc304951273f2adf1a216c44c078753befae48fc69b8` |
| `browser-extension/test/context.test.js` | `c17889c6d0f9bc4f85800ec99abe20e34f59574139c5dab06bc2733e31182613` |
| `browser-extension/test/discovery.test.js` | `08496dbbae375dcbe75f3d750ef03a7fd057a6c0ec7340e1caee45a0a104033c` |
| `browser-extension/test/launcher.test.js` | `a7b40709f882e692c7bd80b1c0936b4d73d849c798d2e2c3cdc69dfea5fd0de6` |
| `browser-extension/test/security.test.js` | `62a88e14c92d33c8ae717cd46b49b5b541c1da489b1f36a76ebb3e2d42e5bcec` |
| `config/initializers/filter_parameter_logging.rb` | `5f26344e1a2f853a925c17240c9800ca57d7180ad2367840f6ee04961c887759` |
| `config/initializers/rack_attack.rb` | `a6f3890de44d75fea377074784ad02c9c2ef2e20e180fff8b8460fe75bb1194e` |
| `config/routes.rb` | `ef0a288df3e91b1112d1d7c1d58c1906daba0103f065d1ffc5da336dd44c6fe6` |
| `db/migrate/20260905203000_create_browser_extension_grants.rb` | `a71eb3e486e4c33193e0efb89c1e319146d3b72b0bd15b4742049ba9462182a9` |
| `db/migrate/20260906013000_add_terms_to_browser_extension_grants.rb` | `a5d5f3ed30f4ab2ce6dfc68e577f4f25eab7a4e1ddc197b6f2206b01a5fdd568` |
| `db/migrate/20260906023000_create_browser_extension_operations.rb` | `0fb6dbda82e1c4714db013b0801f9a22ae988d53a4275c11e58f724c204b6fff` |
| `db/structure.sql` | `d1f08f9684fe618a0e52df2f420fa2a5807cceadb514a4b2786e34d0e94d4f37` |
| `docs/architecture/unitymob-discovery.html` | `fe81abf252592f55114c7fe1f6d0b71abaeb5fe35fd7f93540481febb61da662` |
| `docs/architecture/unitymob-discovery.svg` | `39fa04c9532ebde1eff7713d787662c83e86d0d08a5df8d33f32da614a5baccd` |
| `docs/discovery-v2-activation.md` | `ac07df0e2ddd138ca394dbf604b436ebd75b40e7e74f1e4bc705d85030b1e65e` |
| `docs/whatsapp-browser-extension.md` | `0ecd2634d507775dbcdbf55567e0ca63c1f5f70e03e1d55d6fff8d776f478b28` |
| `gateway/.env.example` | `e87722955c450b82a4233e67c490bee5d846242feb04d0137c7845c5cf9ade1e` |
| `gateway/README.md` | `b18652c6f17259dd684929de36df075bdcb67cce3f0777c85599ad18a60c5df8` |
| `gateway/Rakefile` | `a58408fedad99a5b1a3e74c6f3865f23b187f62a1778009caac5b6bbf4e9d862` |
| `gateway/app/discovery_routes.rb` | `039ff9c534eb4f12dea5c00e14f5cc9013562a0da9c5ffdbedfe808e92f2b97c` |
| `gateway/app/gateway_app.rb` | `57ee208687eeb4d9b466654a43da47b6bd8ebd895d991aba97da48229dcaf633` |
| `gateway/app/models/account_membership.rb` | `58efe40a47d6603e22f4855ec34c69e5ec021747a25136952181da8237872e15` |
| `gateway/app/models/discovery_challenge.rb` | `af5e77b4d54a7b379174206214c346f3726aaacdf8343d822f102c03b2c898ba` |
| `gateway/app/models/discovery_limit.rb` | `5675d5e254baf0727c7c3840e0468a914dedfbfd87060dc87fabfb71b2383247` |
| `gateway/app/services/discovery.rb` | `919b515ddb4d0f5dbeacf16d72bc2a3cff58f45b685eed2fbc3189cd713d7cfe` |
| `gateway/db/migrate/20260906040000_create_discovery_v2.rb` | `d234a5b48df1e03d3bedf680ef96adc4dedcdb9567122972e893d5edf75b223f` |
| `gateway/spec/discovery_delivery_spec.rb` | `69f18711bf1acaaddda7569d2232d712c37253a2d8eeb14e6338f7f643f26c68` |
| `gateway/spec/discovery_spec.rb` | `c5fd5bf350ef804bebcc18181b5f6e257a15bec40036e32483c094d5eb6e8f89` |
| `gateway/spec/spec_helper.rb` | `a57d4e8facb1e728902cad5fe4896f098487458cdc27362409af7b9e66c45f3f` |
| `lib/tasks/discovery.rake` | `462b102c5421fe780f1fc3aefe6c98e24591954482280b75c8f74bfb4e39991f` |
| `spec/requests/api/v1/browser_extension_spec.rb` | `4fa991e780b9a77f7ed82cc7fd4482129062dec4d8954e8369831b4316bf4edd` |
| `spec/services/mobile/account_membership_registrar_spec.rb` | `811623f36377ea84cc05a2d62b446b2c7a47d75cde7f179c8958efa3621da1c5` |
