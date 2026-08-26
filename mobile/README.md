# Unitymob Field — app híbrido (Capacitor)

Wrapper nativo do PWA `/field` (o mesmo painel do corretor que já existe no app
Rails principal). O app **não reimplementa nenhuma tela**: ele resolve o
servidor da conta e navega o WebView direto pras páginas reais do Rails, com
login por cookie normal — exatamente como abrir o site num navegador mobile.

## Como funciona

1. Ao abrir pela primeira vez, mostra uma tela local (`www/index.html`) com
   e-mail + senha, estilizada igual à tela real de login.
2. No "Entrar": chama o gateway de discovery (`POST /discovery/resolve` no
   serviço `gateway/`) com o e-mail pra descobrir a URL do servidor daquele
   cliente (cada conta pode estar num servidor/IP físico diferente).
3. Envia um POST real de formulário (não fetch — não esbarra em CORS) pra
   `{tenant_url}/mobile/sign_in`, um endpoint que herda toda a lógica de
   `Admin::SessionsController` (mesma checagem de senha, política de acesso,
   2FA, `remember_me` de 6 meses) e só dispensa CSRF — necessário porque essa
   primeira requisição vem de outra origem.
4. A resposta redireciona pro `/field` (sucesso), desafio de 2FA, ou de volta
   pra tela real de login com o erro — sem nenhum tratamento especial no app.
5. A URL do servidor fica salva localmente (`localStorage`): próximas
   aberturas pulam a tela de login e vão direto pro `/field` — o cookie
   decide se ainda está autenticado. Logout explícito ("Sair") redireciona de
   volta pra essa tela local (ver `Admin::SessionsController#after_sign_out_path_for`,
   que detecta o app nativo pelo User-Agent `UnitymobFieldApp`).

## Rodando localmente (spike/dev)

```bash
cd mobile
npm install
npx cap sync ios
npx cap run ios   # abre no simulador
```

Pra testar contra um servidor local (Rails rodando em `127.0.0.1:PORTA`),
edite temporariamente `www/index.html`:

```html
<script>window.UNITYMOB_DISCOVERY_URL = "http://127.0.0.1:4001/discovery/resolve";</script>
```

e adicione a exceção de ATS no `Info.plist` (`NSAppTransportSecurity` /
`NSAllowsArbitraryLoads`) — **reverta os dois antes de qualquer build de
staging/produção**, onde tudo é HTTPS.

## Configuração por ambiente (staging/produção)

`www/index.html` usa `https://webhooks.unitymob.com.br/discovery/resolve`
como padrão de produção. Para múltiplos ambientes, isso deveria virar um
build step (ex.: `www/config.staging.js` vs `config.production.js`,
selecionado no CI antes do `cap sync`) — ainda não existe, é o próximo passo
natural antes de builds de release.

## Push notifications

**Ainda não há credenciais reais configuradas.** O código já está pronto,
falta só isso:

1. **Se for usar Firebase Cloud Messaging (recomendado — cobre iOS e Android
   com uma configuração só):**
   - Criar um projeto em https://console.firebase.google.com
   - Gerar uma service account key (Configurações do projeto → Contas de
     serviço → Gerar nova chave privada) — isso baixa um JSON.
   - No servidor Rails, definir:
     - `FCM_PROJECT_ID` = id do projeto Firebase
     - `FCM_SERVICE_ACCOUNT_JSON` = conteúdo do JSON (a string inteira, não o path)
   - No Firebase, subir a chave APNs (.p8) do seu Apple Developer account em
     Configurações do projeto → Cloud Messaging → Apple app configuration,
     pra ele conseguir entregar no iOS também.

2. **No Xcode** (precisa de conta Apple Developer):
   - Abrir `ios/App/App.xcworkspace` no Xcode.
   - Selecionar o target App → aba "Signing & Capabilities" → "+ Capability"
     → "Push Notifications". Isso religa `App.entitlements` (já existe aqui,
     com `aps-environment: development` como ponto de partida) ao projeto.
   - Trocar `aps-environment` pra `production` num build de release (o Xcode
     geralmente cuida disso sozinho a partir da capability).

3. **Limitação importante**: o Simulador do iOS **não recebe push remoto em
   nenhuma hipótese** — é uma limitação da Apple, não deste app. Validar
   entrega de verdade exige um iPhone físico com a build instalada.

O que já está implementado e testado (specs no app principal):
- `PushSubscription` aceita tanto Web Push (PWA, chaves p256dh/auth) quanto
  device token nativo (`platform: "ios"|"android"`, sem essas chaves).
- `POST /field/push_subscriptions/native` registra o token do app híbrido.
- `Notifications::PushDispatcher` escolhe automaticamente Web Push ou FCM
  (`Notifications::FcmSender`) por assinatura, na mesma chamada que já
  dispara notificação pro PWA.
- `app/views/layouts/field.html.erb` pede permissão e registra o token via
  `@capacitor/push-notifications` quando roda dentro do app nativo (detecta
  pelo User-Agent `UnitymobFieldApp`, configurado em `capacitor.config.json`)
  — no PWA/navegador comum, continua no fluxo de Web Push de sempre.

## Geolocalização e outras funcionalidades nativas

Ainda não implementado — mesma lógica do push: o service worker atual
(`field-service-worker.js`) não consegue rastrear localização em background
dentro do WebView do app híbrido. Precisa de `@capacitor/geolocation` +
configuração nativa de background location (iOS `UIBackgroundModes`, Android
foreground service). Fica como próximo passo.

## Plataforma Android

Ainda não adicionada neste checkout — o ambiente usado não tinha Android
SDK/emulador disponível pra build e verificação real. `npx cap add android`
adiciona o projeto; precisa validar em Android Studio antes de considerar
pronto (não faça isso sem poder testar de verdade).
