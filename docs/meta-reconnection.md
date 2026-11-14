# Reconexão Meta sem perder a configuração

## Causa

A desconexão destruía UserMetaIntegration e, por dependência, suas páginas e formulários. Na reconexão, selected_page_ids ficava vazio. MetaSyncJob descobria as páginas autorizadas, mas não consultava formulários nem ativava o Instagram de páginas não selecionadas. A seleção estava restrita à impersonação do suporte.

## Comportamento

- Desconectar registra disconnected_at, apaga os tokens da integração e das páginas e desativa páginas/Instagram. Preserva seleção, formulários, anúncios e configurações do perfil.
- Reconectar reutiliza a integração do mesmo usuário e tenant, remove disconnected_at e agenda a sincronização completa existente. A seleção continua sujeita à autorização atual da Meta; páginas não retornadas ficam inativas e o motivo aparece na tela.
- Usuários com manage:integracoes podem selecionar páginas autorizadas na própria conexão, em Selecionar páginas. IDs de outras integrações são recusados. Consultas amplas de contas de anúncios continuam restritas ao suporte.
- Na primeira conexão, é necessário escolher explicitamente as páginas da empresa. Não se ativam todas as páginas de um login de agência automaticamente.
- Jobs pendentes de uma conexão desconectada não iniciam sincronização nem reativam suas páginas. A rotina periódica já ignora conexões sem token.
- O catálogo de seleção também permanece disponível após o broadcast que atualiza a tela.

## Publicação

Requer a migration 20261113210000 antes da ativação do código. Nenhum backfill ou mudança de configuração de outras contas. O rollback de código deve anteceder a remoção da coluna; voltar ao comportamento antigo torna a desconexão destrutiva novamente.

A sincronização verifica rotas no gateway e inscrições de formulários/Instagram pelo fluxo existente. Permissões revogadas na Meta exigem nova autorização do responsável. Não se reprocessam leads históricos.
