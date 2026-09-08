# Aceite dos termos da extensão

## Registro existente

`browser_extension_grants` relaciona cada aceite ao `admin_user_id` e `tenant_id`, com `terms_accepted_at`, `terms_version` e SHA-256 em `terms_digest`. Também há o ID da extensão e vínculo opcional com dispositivo confiável. O endpoint autenticado exige aceite explícito da versão e hash vigentes. Não há snapshot integral do documento nem IP/user-agent específicos do evento de aceite nesses campos.

## Reutilização entre logins

`BrowserExtensionGrant#terms_acceptance` consulta o registro original do mesmo usuário/tenant e exatamente a mesma versão/hash. A nova concessão não recebe uma data de aceite artificial. A expiração ou revogação da credencial não revoga, por si só, o aceite. Novo usuário, outra conta, alteração da versão ou do conteúdo exige aceite próprio. As verificações de autorização, expiração do token e permissões continuam independentes.

Não precisa de backfill: aceites já existentes podem ser consultados diretamente. A mudança requer deploy do Rails, sem novo pacote de extensão. Não foi publicada nesta tarefa.

## Limites da prova

Vínculo autenticado, data, versão e hash fornecem evidências técnicas, mas não garantem isoladamente validade jurídica. Aceite contratual não equivale a consentimento genérico LGPD para todos os tratamentos. A MP 2.200-2, art. 10, parágrafo 2, admite outros meios de autoria/integridade nas condições legais; a LGPD art. 8 exige demonstração da manifestação de vontade quando consentimento for a base aplicável.

O usuário possui `dependent: :destroy` para concessões: excluir o usuário pode eliminar o registro. Preservação da prova, cópia integral/versionada dos documentos, retenção, revogação de consentimento e base legal devem ser tratados numa política própria, sem inventar dados de evidência históricos.

## Validação

Cinco exemplos focados em aceite passaram, incluindo novo login após expiração/revogação, vínculo ao registro original, isolamento entre usuário/tenant e mudança do hash. A suíte de extensão apresentou uma falha adjacente de escopo de agenda (`spec/requests/api/v1/browser_extension_spec.rb:101`), reproduzida também com o método anterior, sem esta correção.

## Opção de sessão de 30 dias

Checkbox `Manter conectado por 30 dias neste navegador`, desmarcado por padrão, no painel de login. O worker encaminha somente a opção booleana; o servidor aceita apenas `remember=1` e vincula a escolha ao cookie criptografado de autorização. O redirecionamento após senha/TOTP preserva a escolha. O POST não pode fornecer prazo arbitrário ou sobrescrever a escolha. O desafio de conexão continua válido por cinco minutos; somente a credencial final passa a durar 30 dias quando solicitado, permanecendo oito horas por padrão.

Revogação, expiração e verificações de acesso continuam aplicáveis. Tokens existentes não são estendidos. Texto dos termos atualizado para v6 e páginas públicas correspondentes ajustadas no checkout: o novo texto exige um aceite explícito único antes de reutilização futura. Necessita deploy Rails/publicação dos textos e novo pacote da extensão. Releases 0.4.10 já entregues não foram alteradas.
