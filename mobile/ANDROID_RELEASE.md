# Release Android — Google Play

Pacote: `br.com.unitymob.field`. Primeira versão: `1.0` (`versionCode 1`).
Arquivo gerado: `output/google-play/unitymob-1.0-1.aab` (a partir da raiz do repositório).

## Assinatura

A chave de upload está fora do Git em `~/.android/unitymob-upload/unitymob-upload.p12`,
alias `unitymob-upload`. A senha está em `~/.android/unitymob-upload/password.txt`.
Ambos têm permissão 600. Faça backup seguro dessa pasta para futuras atualizações.
Não envie a chave ou a senha junto com o AAB. Ative o Play App Signing no Console.

## Reproduzir

Na pasta `mobile`:

```sh
node --test test/release-login.test.cjs
npx cap sync android
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew bundleRelease lintRelease testReleaseUnitTest
```

Na raiz do repositório:

```sh
mkdir -p output/google-play
/opt/homebrew/opt/openjdk@21/bin/jarsigner -keystore "$HOME/.android/unitymob-upload/unitymob-upload.p12" -storepass:file "$HOME/.android/unitymob-upload/password.txt" -sigalg SHA256withRSA -digestalg SHA-256 -signedjar output/google-play/unitymob-1.0-1.aab mobile/android/app/build/outputs/bundle/release/app-release.aab unitymob-upload
/opt/homebrew/opt/openjdk@21/bin/jarsigner -verify output/google-play/unitymob-1.0-1.aab
```

Aumente `versionCode` em `android/app/build.gradle` antes de enviar uma atualização.
O certificado de upload é autoassinado; os avisos de cadeia/timestamp do jarsigner são esperados.

## Validação desta versão

- Build release, lint e testes unitários Android concluídos.
- Sete testes de login: HTTPS aceito; HTTP, URL inválida e credenciais embutidas rejeitados; sessão persistente validada.
- Seletor oculto de ambiente removido; HTTP bloqueado no manifesto Android.
- Integridade ZIP, assinatura e assets empacotados conferidos.
- Lint com avisos de dependências, ícones e recursos; sem erros bloqueantes.
- Sem aparelho conectado: login real, notificações, áudio e demais fluxos precisam de teste no dispositivo.
- Nenhum upload ou envio para revisão foi realizado.
