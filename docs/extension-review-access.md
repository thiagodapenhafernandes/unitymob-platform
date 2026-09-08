# Acesso temporário para revisão da Chrome Web Store

Status: exceção preparada em 07/09/2026; remover após aprovação e publicação.
Marcador de busca no código: `TEMPORARY_CWS_REVIEW`.

## Escopo

- E-mail exato: `web.iprodutora@gmail.com` (normalizado por trim/downcase).
- Instância `conexao`, tenant `72`, origem `https://app.conexaobc.com`.
- Usuário existente `1527`, ativo, perfil Corretor, sem superadministrador.
- Verificação operacional: não vê todos os leads nem a equipe; possui 5 leads próprios. Não se atestou que sejam fictícios. O catálogo comercial da imobiliária permanece disponível conforme as permissões existentes.
- Senha de avaliação ajustada no servidor e validada; não armazenar a senha no código, pacote ou documentação versionada.
- Nenhum bypass da senha, MFA do CRM, autorização, aceite dos termos ou escopo da API. Apenas a descoberta por código de e-mail é pulada para esse endereço.
- Os demais e-mails, inclusive aliases, continuam no fluxo normal.
- Não há prazo automático: aprovação/publicação é um evento externo. A remoção exige nova versão da extensão.

## Arquivos e reversão

1. Em `browser-extension/src/background.js`, remover o bloco `TEMPORARY_CWS_REVIEW` de `discovery_start` (o `if` completo).
2. Em `browser-extension/src/panel.js`, remover o retorno antecipado marcado com `TEMPORARY_CWS_REVIEW`. Manter `showDiscoveryAccounts`, que também serve ao fluxo normal.
3. Em `browser-extension/test/discovery.test.js`, remover os dois testes temporários e adicionar a regressão de que o e-mail de revisão voltou a solicitar o código.
4. Executar a suíte JavaScript e gerar o pacote com a configuração de discovery vigente. Atualizar a pasta descompactada e enviar a versão normal à loja.
5. Trocar a senha de avaliação por uma senha forte e revogar as concessões de extensão/sessões desse usuário. Não excluir o usuário ou seus leads existentes como parte da reversão.
6. Retirar as credenciais temporárias das instruções de teste da loja e registrar a conclusão neste documento.

## Pendência antes de enviar à loja

A Conexão atualmente autoriza somente o ID da extensão descompactada `hokkkaibgfilkmgaohfblcigmhlppdhl`. Confirmar o ID exato do item da Chrome Web Store e adicioná-lo à configuração autorizada do servidor antes de testar o pacote da loja. Não foi alterada essa configuração nesta tarefa.

## Mais instruções (menos de 500 caracteres)

Abra o WhatsApp Web com uma conta de teste própria. Abra a extensão e informe o e-mail fornecido; esse acesso de avaliação não solicita código por e-mail. Clique em Entrar em Conexão Imobiliária, use a senha fornecida, autorize a extensão e aceite os termos. Abra uma conversa de teste. Teste Lead, busca/filtros de imóveis, galeria, associação e tarefas. Envie imóveis apenas à conversa de teste. Não altere nem envie dados de clientes reais.

## Empacotamento para a loja

Usar `UNITYMOB_WEB_STORE=1` junto às variáveis de origem do build. Esse modo gera `dist-webstore` sem o campo `key`, evitando conflito com o item existente na loja. O build descompactado mantém sua chave. Para 0.4.6, usar `unitymob-whatsapp-0.4.6-webstore.zip`; o ZIP sem esse sufixo foi rejeitado por conter a chave local. A autorização do ID da loja no CRM continua necessária.
