# Consulta de contatos e documentos dos imóveis

Em **Conta → Perfis → Editar → Imóveis → Contatos e documentos internos**, o campo
**Quem pode consultar** controla os contatos do proprietário e os documentos
internos (fichas, autorizações e demais anexos) nos imóveis que o usuário já pode
abrir. A configuração vale para todas as contas.

- **Apenas os próprios**: imóveis com o usuário como responsável ou corretor vinculado.
- **Equipe (subárvore)**: inclui o próprio usuário e todos os seus subordinados nas
  hierarquias de vendas e locação, pelos vínculos cadastrados.
- **Todos os imóveis da conta**: permite consultar esses dados nos imóveis
  acessíveis da mesma conta, inclusive fora da equipe e da área de atuação.
- **Manter regra atual**: não configura um novo escopo; preserva os critérios anteriores.

Perfis existentes permanecem na regra atual até uma escolha explícita. O escopo
fica no JSON de permissões do perfil, em `imoveis.internal_data_scope`; não há
migration ou alteração automática dos perfis de produção.

Se o perfil vertical e a função horizontal definirem um escopo, vale o mais
restrito. Se apenas um definir, vale esse escopo. O dono da conta conserva seu
acesso administrativo. A configuração não concede acesso a outra conta, edição,
exclusão, comissões, exportação nem ao cadastro global de proprietários. Essas
permissões continuam sendo controladas pelos recursos e campos existentes.

O controle é aplicado ao catálogo, detalhes do imóvel, contato na fotografia da
captação e consulta no formulário. A gestão de documentos permanece separada.
Links assinados de anexos já emitidos mantêm o comportamento existente do Active
Storage; este ajuste não modifica o mecanismo de entrega de arquivos.
