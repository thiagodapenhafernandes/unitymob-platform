# Portais — opção 2

final result: passed

Target: /Users/thiagodap.fernandes/.codex/generated_images/01a11639-bfe6-7f61-b03e-e0974ecccedd/exec-92b05f29-cb1e-49fc-b721-e7ed95be15cf.png
Implementation: https://dev.unitymob.com.br/admin/portal_integrations?portal=zapimoveis#portal-leads (checkout local exposto pelo ambiente de desenvolvimento).
Desktop evidence: /tmp/unitymob-portais-option2-final.jpg
Mobile evidence: /tmp/unitymob-portais-option2-mobile.jpg

Scope: hierarchy and functional composition of the selected concept, preserving existing shared admin primitives and authenticated account identity. The concept uses synthetic data and a configured Gateway; the running environment has no Gateway configured. Its missing URL is an intentional real state, not a simulated working connection. Live portal delivery was not validated.

First inspection: horizontal navigation rendered vertically without its shared underline variant; advertiser label did not target its custom field ID; instructions inherited excess grid spacing. Fixed with existing underline variant, explicit label target and grouped instruction content. Recaptured after fixes.

Comparison: reference and final capture opened together. Desktop captured at normal browser dimensions; a 1440×1024 capture was also inspected, with browser capture scaling, so this is not a pixel-exact fidelity claim. Navigation, form-left/status-right composition, selected underline, restrained blue/gray tokens and readable typography match the direction. Existing header, tenant logo and dense admin spacing deliberately retained. No new raster assets or icon library needed; Bootstrap icons reused.

Interaction checks: both tabs switch and hide the other panel; input has associated label; saves return to leads via URL hash. Request tests cover account isolation, persisted advertiser identification, preserved publication filters, permissions and feed behavior.

Mobile: 390×844 viewport inspected, scrollWidth equals innerWidth (390), form/status/instructions stack without horizontal overflow. Existing main-list navigation and portal chooser preserved. P3: portal list remains long on mobile; compact portal selection could be a separate improvement.

Validation: 22 request/job/feed examples passed; admin Tailwind build passed; git diff --check passed. No production deploy.
