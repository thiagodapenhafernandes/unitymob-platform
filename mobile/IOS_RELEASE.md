# Atualização iOS — Unitymob

Pacote preparado: **1.0.1 (6)**, bundle `br.com.unitymob.field`, equipe `J9956N9B6A`.
A versão 1.0 já está publicada. Este pacote inclui os quatro sons de notificação.

Ícone original restaurado byte a byte do commit `767e7175`, anterior à troca de
09/09. Este pacote substitui os builds 4 (rejeitado por alpha) e 5 (ícone mais
recente com alpha removido).

Archive local gerado e verificado em:
`~/Library/Developer/Xcode/Archives/2026-09-12/Unitymob 1.0.1 (6).xcarchive`.
Verificados: assinatura, bundle, versão/build, os quatro WAV idênticos às prévias
e ícone de 1024x1024 opaco no Assets.car (PNG de origem RGB, sem alpha).
O digest do ícone compilado foi comparado com o Archive 1.0 (3) de 02/09:
idêntico. Ainda não enviado à Apple; teste no aparelho continua pendente.

Nesta máquina, o Xcode 26.6 travou na sondagem `clang -v -E -dM`.
O archive foi gerado com um wrapper temporário que remove somente `-v` dessa
sondagem; macros foram comparadas byte a byte e a compilação/assinatura usam
as ferramentas originais da Apple. Log e wrapper estão em
`outputs/ios-1.0.1-build-4/`, fora do pacote do app.

## Gerar o pacote

1. Abrir `ios/App/App.xcodeproj` no Xcode.
2. Selecionar o scheme **App** e **Any iOS Device (arm64)**.
3. Conferir no target App: Version **1.0.1**, Build **6** e assinatura automática
   com a equipe existente. Se o build 6 já tiver sido enviado, incrementar.
4. Usar **Product → Archive**. O archive deve aparecer no Organizer.
5. Conferir versão, bundle, assinatura e os quatro `unitymob_*_v1.wav` no pacote.

Não é necessário atualizar dependências para esta mudança de sons. Se houver
mudanças em plugins ou `www`, executar `npx cap sync ios` dentro de `mobile` antes
do Archive e revisar os arquivos gerados.

## Distribuição (depois de autorizar o envio)

1. No Organizer, selecionar o archive e usar **Distribute App → App Store Connect**.
2. Conferir as opções e concluir o upload. O Xcode pode precisar da conta Apple
   autenticada e da assinatura de distribuição; não trocar o bundle/equipe.
3. Aguardar o processamento e disponibilizar o build no TestFlight para teste.
4. Validar login, navegação, notificações, abertura ao tocar e os quatro sons,
   com app aberto, em segundo plano e tela bloqueada. Respeitar silêncio/Foco.
   Os sons por categoria exigem que o servidor de teste envie o novo payload;
   o servidor antigo ainda manda `sound: default`.
5. No App Store Connect, criar a versão **1.0.1**, selecionar o build validado,
   preencher as novidades e enviar para revisão, mantendo a distribuição vigente.
6. Quando a atualização estiver disponível, publicar o servidor Rails e fazer
   o teste final de ponta a ponta nos aparelhos atualizados.

Sugestão para “Novidades”: **Novos sons para diferenciar notificações de leads,
Bolsão, lembretes e avisos gerais.**

Referências: [Archive](https://help.apple.com/xcode/mac/current/en.lproj/devf37a1db04.html),
[Upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[Nova versão](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version).
