# Extensão 0.4.2 — imóveis de interesse

Implementação local, ainda não publicada. Pasta instalada dist permanece 0.4.1 até atualização das APIs. Build e ZIP 0.4.2 estão em browser-extension/dist-discovery e browser-extension/unitymob-whatsapp-discovery-0.4.2.zip.

- Busca automática com debounce de 300 ms; código numérico filtra prefixo de código, evitando coincidências nas descrições. Busca textual reutiliza admin_search_text para empreendimento/localização.
- Filtros recolhidos: preço mínimo/máximo em reais (conversão para centavos no backend), suítes, dormitórios e vagas mínimos; venda/locação preservadas. Tenant e disponibilidade mantidos.
- Resultados compactos e roláveis; seleção múltipla preservada entre pesquisas, até 20 por operação.
- Interesses em linhas compactas com faixa laranja, seleção para compartilhar e remoção de interesses (imóvel principal preservado).
- Envio imediato somente após confirmação com destinatário e imóveis. Worker consulta novamente o lead autenticado, aceita somente links públicos relativos da API, verifica telefone e contexto ativo; adapter verifica conta e conversa imediatamente antes de sendTextMessage. Sem envio automático em testes, sem retry automático de envio incerto.
- Termos v4 para compartilhamento confirmado. Sem migration.

Validação: 41 exemplos Rails, 45 testes JavaScript, build, sintaxe, IDs HTML e Zeitwerk. Testes cobrem preço/código, isolamento e permissões anteriores, remoção idempotente, preservação do principal, confirmação de envio e bloqueio na troca de conversa. Interface e envio real ainda precisam de validação autenticada no navegador.

Publicação necessária: Salute e Conexão (mina all deploy), depois atualizar a pasta dist e recarregar o Chrome. Central e Gateway não precisam de deploy. Não incluir WIP independente de filtros/admin/mobile.

## Ajustes dos blocos

Atalhos coloridos removidos; ícones transferidos para títulos de Agenda, Tarefas, Etiquetas, Histórico e Imóveis. O mesmo botão abre/fecha cada formulário, com aria-expanded e indicação +/−. Botões separados de fechar removidos. Disclosures animam altura em 180 ms; estados, cards e menus têm transições curtas, respeitando prefers-reduced-motion. Build, sintaxe e referências DOM validados; 45 testes JavaScript passaram. Inspeção visual no Chrome ainda pendente.

## Pacote final autorizado para produção

Inclui header com saudação/menu, card de lead sem cabeçalho duplicado, imóveis acima das ações, cards de três linhas fixas, título factual, dados financeiros e físicos, URL por código e domínio público do tenant, loading no envio. Filtros com máscara em reais, categoria e regras rápidas compartilhadas com admin via HabitationQuickFilters. Sessão preserva formulários em verificações passivas e inclui correção/teste da restauração sem lead carregado.

Validações finais: 43 exemplos da API Rails, 46 testes JavaScript, Zeitwerk, build e referências DOM. Usuário testou interativamente a extensão local. Pacote de produção usa Gateway de descoberta e permite escolha da imobiliária. Termos v4 requerem aceite.
