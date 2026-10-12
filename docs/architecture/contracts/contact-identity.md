# Contatos internos

`Leads::InternalContactScope.new(tenant:)` exige conta persistida. `matching` retorna relation dos leads internos; `exclude(scope)` aplica a conta e remove esses contatos, preservando filtros do consumidor.

A identidade permanece a anterior: usuários `account_members`, telefone principal e secundário normalizados por `Phones::Normalizer`; comparação por dígitos exatos em `leads.phone` ou `client_phone`. Não adiciona variantes de DDI/nono dígito nem matching por email. Nenhum telefone interno: matching vazio e exclusão sem remoção.

Dashboard só exclui. `InternalContactCleanup` mantém dry-run padrão e remoção explícita, em transação por lead. A query não destrói dados. Mudança de identidade deve ser uma demanda separada, com comparação de IDs e avaliação do efeito destrutivo.
