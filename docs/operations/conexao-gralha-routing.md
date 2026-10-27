# Distribuição por natureza e modalidade da entrada

Implementação local; sem configuração de produção, replay ou alteração de registros históricos.

## Ordem da decisão

1. Natureza: pedido administrativo, consulta comercial ou contato sem intenção identificada. Pedidos de financeiro/manutenção e atendimentos administrativos abertos ficam no atendimento, sem tomar o lead do corretor.
2. Modalidade da consulta atual: dado estruturado (`business_type`/`negotiation_type`, incluindo RD), imóvel vinculado da própria conta e sinais do formulário, URL e mensagem/anúncio de entrada. Sem usar nome da campanha, status, observações ou interesses antigos do contato. Modalidades: venda, locação, ambas ou desconhecida.
3. Filas ativas da própria conta, origens e modalidade da interface. Regras de atendimento administrativo não entram no rodízio comercial automático. Modalidade desconhecida não é considerada venda nem locação; uma fila ampla `ambos` pode recebê-la se a entrada já for comercial. Contato WhatsApp sem intenção permanece na triagem.
4. Filtros adicionais opcionais de campanha/formulário/preço. Campanha usa ID exato e não é obrigatória. Um filtro nunca transforma uma modalidade incompatível em outra. Destinos concorrentes para nova entrada WhatsApp ficam para triagem.
5. Distribuição existente: participantes elegíveis, check-in, horário, represamento, bolsão, fidelização e notificações configuradas. Sem regra compatível por origem, mantém-se a contingência explicitamente configurada; modalidade ausente com filas específicas é bloqueada antes da contingência genérica.

## Conexão

A Gralha Azul pode seguir para a fila de vendas já configurada quando a entrada informar venda ou apontar para imóvel de venda. Não é necessário cadastrar uma regra por campanha.

O ID `120250339532760049` somente deve ser usado como filtro opcional caso a conta queira um destino exclusivo. Não acrescentar esse filtro à fila genérica de vendas, pois restringiria outras campanhas. Exclusividade Notre Dame continua dependente da regra da conta.

Se o RD enviar apenas `Form - Refuge`, sem modalidade/imóvel, não se deduz venda pelo nome. O RD pode enviar `business_type: sale` (ou `rental`/`sale_rent`, `negotiation_type` ou `cf_tipo_negocio`). A consulta atual e a origem inicial são preservadas separadamente.

A conta local correspondente é `1000072` (Conexão Imobiliária); o ID em produção é `72`. Em 27/10/2026, somente as configurações locais das filas ativas foram alinhadas por leitura da produção: locação com Letícia, vendas com cinco participantes e Notre Dame com Augusto e seus três formulários. A regra de migração permanece inativa. Os 5.888 leads locais permaneceram idênticos, verificados por hash de todos os campos antes/depois.

O receptor RD obedece à origem e à modalidade padrão da interface da própria conta. Modalidade explícita no payload tem prioridade; `auto` mantém a detecção sem presumir venda. A fonte de transporte RD continua identificada por `lead_type`, mesmo com origem personalizada. Nenhum padrão comercial foi ativado em produção.

Os filtros opcionais são editáveis no painel compartilhado de linhas repetíveis. Podem usar atributos do lead, respostas e metadados da entrada; chaves nunca executam métodos Ruby. Linhas inteiramente vazias são removidas; filtros incompletos impedem o salvamento.

## Entrada e segurança

Somente a mensagem inicial nova agenda classificação. Sem anúncio, classifica diretamente; com anúncio, aguarda a tentativa de enriquecimento existente. Sem integração Meta, dados locais suficientes ainda permitem classificação. Erros da API mantêm os retries existentes; o nome do anúncio/campanha não substitui modalidade.

Enriquecimentos antigos executados sem o argumento da nova mensagem continuam apenas enriquecendo. Job idempotente, escopado por conta e mensagem, não modifica cadastro já comercial/atribuído nem redistribui contatos antigos. Rosani e os demais casos históricos ficam para decisão posterior.

Publicação, configuração externa do RD e validação com nova mensagem real permanecem pendentes de autorização.
