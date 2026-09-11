# Chrome Web Store — Unitymob para WhatsApp

Atualizado em 10/09/2026. Pacote preparado: **0.4.13**. Ainda não enviado à loja.

## Identificação e pacote

- Item existente: `anpohhipfkehheinckhpgbphcibifocm`.
- ZIP: `browser-extension/unitymob-whatsapp-0.4.13-webstore.zip`.
- Pasta de teste local: `browser-extension/releases/0.4.13` (ID de desenvolvimento preservado).
- Manifest V3; Chrome 116 ou posterior.
- A consulta pública à loja não revelou a versão publicada. Conferir a versão no painel antes de enviar; ela deve ser inferior a 0.4.13.
- Atualizar o item existente, sem criar outra extensão.

## Textos para a loja

**Nome:** Unitymob para WhatsApp

**Descrição curta:** Consulte e crie leads, registre notas e agende tarefas durante o atendimento no WhatsApp Web.

**Descrição completa:**

Acesse o atendimento da sua imobiliária na Unitymob enquanto conversa no WhatsApp Web.

Consulte e cadastre leads, acompanhe o histórico de contatos, registre notas, organize tarefas e compromissos. Pesquise imóveis, consulte fotos, vincule imóveis ao atendimento e compartilhe seus links na conversa após confirmação.

Abra o WhatsApp Web, clique na extensão e entre com sua conta Unitymob. Escolha a imobiliária autorizada e aceite os termos para acessar o painel. É necessária uma conta ativa com as permissões correspondentes.

O acesso respeita as permissões da imobiliária. A extensão não coleta o histórico de mensagens do WhatsApp e não envia mensagens sem sua confirmação. Você pode desconectar a conta pelo painel.

Suporte: contato@unitymob.com.br.

**Finalidade única:** Integrar o atendimento imobiliário da Unitymob à conversa atual no WhatsApp Web.

**Idioma:** Português (Brasil).

**Categoria sugerida:** Produtividade; preservar a categoria existente se já aprovada.

## Justificativas de permissões

| Permissão | Justificativa |
| --- | --- |
| sidePanel | Display the real estate CRM next to the current WhatsApp Web conversation. |
| storage | Store the authorized session, consent and interface preferences locally, plus operation identifiers that prevent duplicate submissions. |
| scripting | Read the current WhatsApp contact and perform property-link sharing only after the user confirms the action. |
| identity | Authenticate the user with their Unitymob account using the browser's secure sign-in flow. |
| https://web.whatsapp.com/* | Identify the currently selected contact and send selected property links after explicit user confirmation. |
| https://anpohhipfkehheinckhpgbphcibifocm.chromiumapp.org/* | Complete the authentication callback for this extension's existing store identity. |
| https://webhooks.unitymob.com.br/* | Discover the Unitymob accounts available to the email entered by the user. |
| https://*/* (opcional) | Each real estate company may use its own HTTPS CRM domain. Access is requested for the selected account's domain during connection and for the specific image hosts of selected properties when sharing. Image access prepares the preview before sending; this is not automatic access to all websites. |

Nenhuma permissão nova foi acrescentada nesta preparação.

## Privacidade e uso dos dados

- Política: https://unitymob.com.br/politica-de-privacidade.html
- Dados usados: e-mail de login, identidade e telefone do contato selecionado, credencial de autenticação, dados comerciais autorizados e informações que o usuário confirma no atendimento.
- A credencial e as preferências ficam no armazenamento local; informações transitórias de autenticação usam armazenamento de sessão.
- Destinatários: a conta Unitymob escolhida e o serviço de descoberta de contas, conforme a política.
- Não há coleta do histórico de mensagens, venda de dados ou publicidade personalizada.
- O código executável e as bibliotecas estão incluídos no pacote; não há dependência de download remoto de código para a atualização.
- Manter as declarações de dados do painel coerentes com a política, incluindo identificação pessoal, autenticação e dados do atendimento. Não declarar “nenhum dado coletado”.

## Imagens e acesso para revisão

- Ícones 16, 32, 48 e 128 px incluídos no pacote.
- Reutilizar as imagens já cadastradas na loja se ainda representarem a interface; nenhuma nova captura foi criada nesta preparação.
- Instruções existentes de acesso para revisão: `docs/extension-review-access.md`. Credenciais não devem ser incluídas no ZIP nem neste documento.

## Histórico

### 0.4.13 — 10/09/2026

- Compartilhamento solicita acesso apenas aos domínios das fotos selecionadas antes do envio, corrigindo o bloqueio de leitura no CDN. Negar a permissão preserva a seleção e não envia mensagens.
- Download e preparação da foto continuam sendo aguardados antes de enviar.
- Validação com envio real no Chrome ainda pendente.

### 0.4.12 — 10/09/2026

Seleção de atendimentos com cartões alinhados à esquerda, nome e código separados, status em destaque e responsável, origem e data com hierarquia visual. O atendimento carregado fica destacado, com estado de seleção acessível. Mesmos dados, permissões e fluxo de atendimento.

### 0.4.11 — 10/09/2026

Pacote de atualização que consolida o código integrado da 0.4.10: compartilhamento confirmado de imóveis, tratamento de repetição sem duplicar envios, persistência do login, filtros do catálogo e navegação do atendimento. Sem funcionalidade adicional introduzida nesta preparação.

### 0.4.10

Versão encontrada no código antes desta preparação; isso não comprova a versão publicada na loja.

## Validação e envio

- 100 testes JavaScript passaram.
- Builds de loja e teste local gerados pelo script existente.
- ZIP contém o manifesto na raiz e somente arquivos do build; exclui testes, sessões, configurações privadas e documentação.
- Login real no Chrome com o pacote 0.4.13 ainda não foi exercitado nesta preparação.
- Envio: painel do item existente → Pacote → Fazer upload de novo pacote → selecionar o ZIP → conferir os dados → enviar para análise.
- Referência oficial: https://developer.chrome.com/docs/webstore/update
