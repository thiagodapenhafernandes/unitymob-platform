import { readFile, writeFile, mkdir, copyFile, readdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { allowedOrigin } from "../src/security.js";

const root = fileURLToPath(new URL("../", import.meta.url));
const discoveryOrigin = process.env.UNITYMOB_DISCOVERY_ORIGIN || null;
if (discoveryOrigin) allowedOrigin(discoveryOrigin, [discoveryOrigin]);
const webStore = process.env.UNITYMOB_WEB_STORE === "1";
const dist = resolve(root, webStore ? "dist-webstore" : discoveryOrigin ? "dist-discovery" : "dist");
const { version } = JSON.parse(await readFile(resolve(root, "package.json"), "utf8"));
const crmOrigins = (process.env.UNITYMOB_CRM_ORIGINS || "https://dev.unitymob.com.br").split(",").map(s => s.trim());
if (crmOrigins.length !== 1) throw new Error("Configure exatamente uma origem por pacote.");
for (const origin of crmOrigins) allowedOrigin(origin, crmOrigins);
const key = (await readFile(resolve(root, webStore ? "webstore-public-key.txt" : "public-key.txt"), "utf8")).replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
const extensionId = createHash("sha256").update(Buffer.from(key, "base64")).digest("hex").slice(0, 32).replace(/[0-9a-f]/g, c => String.fromCharCode(97 + parseInt(c, 16)));
await rm(dist, { recursive: true, force: true });
await mkdir(resolve(dist, "vendor"), { recursive: true });
await mkdir(resolve(dist, "shared"), { recursive: true });
await mkdir(resolve(dist, "icons"), { recursive: true });
const icons = Object.fromEntries([16, 32, 48, 128].map(size => [size, `icons/icon-${size}.png`]));
for (const path of Object.values(icons)) await copyFile(resolve(root, path), resolve(dist, path));
for (const name of await readdir(resolve(root, "src"))) await copyFile(resolve(root, "src", name), resolve(dist, name));
await writeFile(resolve(dist, "config.js"), `export const crmOrigins = ${JSON.stringify(crmOrigins)};\nexport const crmOrigin = crmOrigins[0];\nexport const discoveryOrigin = ${JSON.stringify(discoveryOrigin)};\n`);
await writeFile(resolve(dist, "manifest.json"), JSON.stringify({
  manifest_version: 3, name: "Unitymob para WhatsApp", version, minimum_chrome_version: "116", ...(webStore ? {} : { key }),
  description: "Consulte e crie leads, registre notas e agende tarefas durante o atendimento no WhatsApp Web.",
  permissions: ["sidePanel", "storage", "scripting", "identity"],
  host_permissions: ["https://web.whatsapp.com/*", `https://${extensionId}.chromiumapp.org/*`, ...(discoveryOrigin ? [`${discoveryOrigin}/*`] : [])],
  optional_host_permissions: ["https://*/*"],
  icons,
  action: { default_title: "Abrir Unitymob", default_icon: icons }, side_panel: { default_path: "panel.html" },
  background: { service_worker: "background.js", type: "module" },
  content_security_policy: { extension_pages: "script-src 'self'; object-src 'none';" }
}, null, 2));
const vendor = resolve(root, "node_modules/@wppconnect/wa-js");
const library = await readFile(resolve(vendor, "dist/wppconnect-wa.js"), "utf8");
// Never overwrite WPP installed by another extension or repeatedly install while loading.
await writeFile(resolve(dist, "vendor/wppconnect-wa.js"), `if (!window.WPP) {\n${library}\n}\n`);
await copyFile(resolve(vendor, "LICENSE"), resolve(dist, "vendor/LICENSE-wa-js"));
for (const name of await readdir(resolve(vendor, "dist"))) {
  if (name.endsWith(".LICENSE.txt")) await copyFile(resolve(vendor, "dist", name), resolve(dist, "vendor", name));
}
const styles = resolve(root, "../app/assets/stylesheets/admin");
await copyFile(resolve(styles, "theme_tokens.css"), resolve(dist, "shared/theme_tokens.css"));
for (const name of ["operational_panel", "property_catalog", "button", "form_control", "stack", "menu"]) {
  await copyFile(resolve(styles, `components/${name}.css`), resolve(dist, `shared/${name}.css`));
}
console.log(`Pacote: ${dist}\nID: ${extensionId}\nWA-JS: 4.6.0\nSem dados de sessão ou arquivos do RD.`);

const iconCss = await readFile(resolve(styles, "../vendor/bootstrap-icons.css.erb"), "utf8");
await writeFile(resolve(dist, "shared/bootstrap-icons.css"), iconCss.replace(/<%= asset_path\("(bootstrap-icons\.woff2?)"\) %>/g, "$1"));
for (const name of ["bootstrap-icons.woff", "bootstrap-icons.woff2"]) await copyFile(resolve(root, "../app/assets/fonts", name), resolve(dist, "shared", name));

await copyFile(resolve(root, "../app/javascript/lib/catalog_controls.js"), resolve(dist, "shared/catalog_controls.js"));
await copyFile(resolve(root, "../app/javascript/lib/currency_filter.js"), resolve(dist, "shared/currency_filter.js"));
await copyFile(resolve(root, "../vendor/javascript/tom-select.js"), resolve(dist, "vendor/tom-select.js"));
await copyFile(resolve(root, "../app/assets/stylesheets/vendor/tom-select.bootstrap5.min.css"), resolve(dist, "shared/tom-select.css"));
