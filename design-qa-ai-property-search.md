# Design QA — busca inteligente por voz no PWA

- Source visual truth: `/Users/thiagodap.fernandes/Downloads/Captura de Tela 2026-07-14 à(s) 01.21.06.png`
- Behavioral evidence: `/Users/thiagodap.fernandes/Downloads/Captura de Tela 2026-07-14 à(s) 07.37.50.png`
- Behavioral evidence: `/Users/thiagodap.fernandes/Downloads/Captura de Tela 2026-07-14 à(s) 07.39.49.png`
- Implementation route: `http://127.0.0.1:3001/field/property_search`
- Intended viewport: mobile, 390 × 844
- States: idle, recording, paused, processing, result/error
- Implementation screenshot: unavailable

## Full-view comparison evidence

Blocked. The supplied source screenshot was available, but this session exposed no controllable in-app browser or Chrome surface to capture the authenticated implementation at the same viewport.

## Focused region comparison evidence

Blocked for the same reason. Code-level inspection confirms that the recording region now contains discard, recording indicator, timer, real microphone waveform, pause/resume and send controls, followed by a persistent processing panel.

## Functional evidence

- Rails request specs validate the PWA markup and authorization gates.
- JavaScript syntax check passed.
- CSS build passed.
- The local route responds on port 3001 and redirects unauthenticated requests to sign-in.
- Primary microphone interaction could not be browser-tested because microphone permission requires an interactive browser surface.

## Findings

- [P1] Rendered recording and processing states were not visually captured.
  - Impact: spacing, mobile wrapping and microphone permission behavior remain visually unverified.
  - Required follow-up: open the authenticated PWA at 390 × 844, record a short audio, pause/resume, send it, inspect the processing state and compare a screenshot with the source.
- [P1] A primeira consulta era interrompida por perguntas complementares.
  - Evidence: as capturas de 07:37 e 07:39 mostram perguntas sobre trecho, bairro e faixa de preço antes de apresentar resultados.
  - Fix: o backend agora ignora perguntas complementares da interpretação, executa imediatamente a consulta exata e só procura uma alternativa controlada após resultado exato igual a zero.
  - Validation: request e service specs cobrem consulta imediata, ambiguidade de empreendimento e sugestão pós-zero. Falta captura visual pós-correção.

## Comparison history

- Initial source finding: the prior screen separated microphone and submit actions and provided insufficient recording/processing feedback.
- Fix implemented: WhatsApp-style recording navigation and persistent processing feedback.
- Second source finding: perguntas complementares bloqueavam a primeira consulta.
- Second fix implemented: consulta imediata; sugestões controladas somente depois de zero resultados.
- Post-fix visual evidence: blocked because no controllable browser is available in this session.

final result: blocked
