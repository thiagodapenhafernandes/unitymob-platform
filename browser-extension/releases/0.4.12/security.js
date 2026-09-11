export const WHATSAPP_ORIGIN = "https://web.whatsapp.com";

export function isWhatsAppTab(tab) {
  try { return new URL(tab.url).origin === WHATSAPP_ORIGIN; } catch { return false; }
}

export function allowedOrigin(value, origins) {
  if (!origins.includes(value)) throw new Error("invalid_origin");
  const url = new URL(value);
  if (url.origin !== value || url.username || url.password) throw new Error("invalid_origin");
  if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname))) throw new Error("invalid_origin");
  return value;
}

export function isPanelSender(sender, runtime) {
  return sender.id === runtime.id && sender.url === runtime.getURL("panel.html") && !sender.tab;
}

export async function createPairing() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const verifier = btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  const challenge = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
  return { verifier, challenge };
}

export function leadId(value) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error("invalid_lead");
  return value;
}
