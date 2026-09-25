# Chrome Web Store Listing — Unitymob para WhatsApp

> Last Updated: 2026-09-23

## Store Listing

**Extension Name**
Unitymob para WhatsApp

**Short Description**
Consulte leads, registre notas, agende tarefas e envie imóveis durante atendimentos no WhatsApp Web.

**Detailed Description**
Unitymob para WhatsApp conecta o atendimento no WhatsApp Web à operação comercial da Unitymob.

A extensão permite localizar ou criar leads durante a conversa, registrar observações, tarefas, etiquetas, histórico de contato e compartilhar imóveis compatíveis sem sair do WhatsApp Web.

Para usar, abra o WhatsApp Web, clique no ícone da extensão e conecte sua conta Unitymob. A extensão identifica a conversa ativa e mostra as ações disponíveis para o lead selecionado.

A extensão acessa apenas o WhatsApp Web e os domínios Unitymob necessários para autenticação e registro das ações solicitadas pelo usuário.

**Category**
Productivity

**Single Purpose**
Apoiar o atendimento comercial da Unitymob dentro do WhatsApp Web.

**Primary Language**
Português (Brasil)

## Package

| Version | File | Status |
|---|---|---|
| 0.4.24 | `browser-extension/unitymob-whatsapp-0.4.24-webstore.zip` | Ready |
| 0.4.23 | `browser-extension/unitymob-whatsapp-0.4.23-manual.zip` | Ready for manual validation |
| 0.4.22 | `browser-extension/unitymob-whatsapp-0.4.22-manual.zip` | Ready for manual validation |
| 0.4.21 | `browser-extension/unitymob-whatsapp-0.4.21-manual.zip` | Ready for manual validation |
| 0.4.20 | `browser-extension/unitymob-whatsapp-0.4.20-manual.zip` | Ready for manual validation |
| 0.4.19 | `browser-extension/unitymob-whatsapp-0.4.19-manual.zip` | Ready for manual validation |
| 0.4.18 | `browser-extension/unitymob-whatsapp-0.4.18-manual.zip` | Ready for manual validation |
| 0.4.17 | `browser-extension/unitymob-whatsapp-0.4.17-manual.zip` | Ready for manual validation |
| 0.4.16 | `browser-extension/unitymob-whatsapp-0.4.16-webstore.zip` | Ready |
| 0.4.15 | `browser-extension/unitymob-whatsapp-0.4.15-webstore.zip` | Ready |
| 0.4.14 | `browser-extension/unitymob-whatsapp-0.4.14-webstore.zip` | Ready |
| 0.4.13 | `browser-extension/unitymob-whatsapp-0.4.13-webstore.zip` | Ready |
| 0.4.13 | `browser-extension/releases/0.4.13.zip` | Ready |

The upload ZIP contains `manifest.json` at the ZIP root and does not include a manifest `key` field.

## Graphics & Assets

| Asset | Dimensions | Status | Filename |
|-------|------------|--------|----------|
| Store Icon | 128×128 PNG | Ready | `icons/icon-128.png` |
| Screenshot 1 | 1280×800 or 640×400 | Needs update | |

## Permissions Justification

| Permission | Type | Justification |
|------------|------|---------------|
| `sidePanel` | permissions | Opens the Unitymob panel beside WhatsApp Web so the user can manage the lead during the conversation. |
| `storage` | permissions | Saves the user's authenticated session, selected account, local drafts, and safe retry metadata. |
| `scripting` | permissions | Loads the Unitymob content script on WhatsApp Web to identify the active conversation and support user-confirmed actions. |
| `identity` | permissions | Completes the Chrome extension authentication callback with Unitymob. |
| `https://web.whatsapp.com/*` | host_permissions | Restricts the extension panel and conversation detection to WhatsApp Web. |
| `https://daliegpkkjjfjjlilajomonpkgdmgiaj.chromiumapp.org/*` | host_permissions | Allows the Chrome identity callback for the published Web Store item. |
| `https://webhooks.unitymob.com.br/*` | host_permissions | Allows account discovery and secure connection with Unitymob services. |
| `https://*/*` | optional_host_permissions | Requested only when the user chooses to prepare and share property images from approved external property/photo URLs. |

## Privacy & Data Use

**Does the extension collect user data?** Yes

| Data Type | Collected? | Transmitted Off-Device? | Purpose | Shared with Third Parties? |
|-----------|------------|-------------------------|---------|----------------------------|
| Personally identifiable info | Yes | Yes, to Unitymob | Associate the active lead/contact with the user's Unitymob account. | No |
| Authentication info | Yes | Yes, to Unitymob | Authenticate the user and keep the session active. | No |
| Personal communications | Limited | Yes, to Unitymob when the user confirms an action | Register notes, history, tasks, labels, and lead actions requested by the user. | No |
| Website content | Limited | Yes, to Unitymob when needed for confirmed actions | Identify the active WhatsApp conversation and prepare selected property sharing actions. | No |
| Web history | No | No | Not collected. | No |
| Location | No | No | Not collected. | No |
| Financial info | No | No | Not collected. | No |
| Health info | No | No | Not collected. | No |

### Data Use Certification

- [x] Data is NOT sold to third parties
- [x] Data is NOT used for purposes unrelated to the extension's core functionality
- [x] Data is NOT used for creditworthiness or lending purposes

## Privacy Policy

**Privacy Policy URL**
TBD before final submission if the dashboard requires a public URL update.

## Distribution

**Visibility**: Public
**Regions**: All regions

## Developer Info

**Publisher Name**
unitymob.apps

**Support URL / Email**
TBD

## Version History

| Version | Date | Changes | Status |
|---------|------|---------|--------|
| 0.4.24 | 2026-09-23 | Keeps property sharing active when photo permission or photo URL validation fails. | Ready |
| 0.4.23 | 2026-09-22 | Sends property links even when thumbnail preparation fails. | Ready for manual validation |
| 0.4.22 | 2026-09-22 | Accepts confirmed Brazilian mobile contacts when WhatsApp and CRM differ only by the ninth digit. | Ready for manual validation |
| 0.4.21 | 2026-09-22 | Restores compact filter/sort CSS and spaces property sends to avoid WhatsApp sequence failures. | Ready for manual validation |
| 0.4.20 | 2026-09-22 | Restores the compact property catalog CSS in the WhatsApp side panel. | Ready for manual validation |
| 0.4.19 | 2026-09-22 | Allows confirmed CRM saves when WhatsApp changes the internal chat id but the account and phone stay the same. | Ready for manual validation |
| 0.4.18 | 2026-09-22 | Shows an explicit reason when a create/save action is blocked before reaching the CRM. | Ready for manual validation |
| 0.4.17 | 2026-09-22 | Opens the create-lead form automatically when no accessible lead is found, avoiding confusion with the disclosure header. | Ready for manual validation |
| 0.4.16 | 2026-09-22 | Aligns the Web Store callback host with the published extension ID used during login. | Ready |
| 0.4.15 | 2026-09-22 | Adds CRM notes fields to appointments and tasks; fixes silent failure when creating tasks or appointments with invalid local date values. | Ready |
| 0.4.14 | 2026-09-22 | Prepares package after task and appointment validation fixes. | Ready |
| 0.4.13 | 2026-09-11 | Store-ready package without manifest key in ZIP. | Ready |
| 0.4.11 | 2026-09-11 | Current published package shown in dashboard. | Published |

## Review Notes

### Upload fix — 2026-09-11

The failed upload happened because a release ZIP contained the manifest inside a version folder and included a manifest `key` field. The 0.4.13 store ZIP now has `manifest.json` at the ZIP root, excludes `key`, excludes macOS metadata files, and keeps the published extension callback host `anpohhipfkehheinckhpgbphcibifocm.chromiumapp.org`.
