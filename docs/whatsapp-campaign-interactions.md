# Indicadores e histórico das campanhas

Os indicadores medem a operação da Unitymob. Integrações externas não definem conversão ou atendimento nestes cards.

- Listagem e grupos usam o mesmo conjunto de campanhas filtradas; as datas filtram a criação da campanha.
- Interações contam destinatários distintos por campanha. No agregado, o mesmo telefone pode contar em campanhas diferentes.
- Cliques contam todas as respostas de botão recebidas, incluindo repetições reais. Reentregas do mesmo webhook não contam novamente.
- Cada botão mostra destinatários distintos e quantidade de cliques. Uma pessoa pode aparecer em mais de um botão.
- Respostas sem botão são contadas separadamente. Botões sem retorno mensurável mostram “Não mensurável”.
- Enviadas e falhas usam o total como denominador; entregues usam enviadas; leituras e interações usam entregues.
- Encaminhamento à fila e aceite do atendimento são confirmações diferentes. Tarefas e outros resultados só aparecem após a ação interna correspondente.

O histórico conserva texto, botão e ação configurada no momento da resposta, além das confirmações de execução. Renomear ou remover um botão não apaga seus eventos. Ações e resultados podem se sobrepor e não devem ser somados como pessoas exclusivas.

A migration `20261114130000_create_whatsapp_campaign_interactions` cria o histórico e vincula atendimentos à resposta de origem. Registros anteriores preservavam somente a última resposta: esse retrato continua nos indicadores, com aviso de histórico incompleto. Não há reconstrução de cliques desconhecidos nem reexecução de ações antigas.

O custo segue as regras de `whatsapp-meta-customer-pricing.md`; indicadores de cliques não são usados para inventar ou repartir cobrança oficial da Meta.
