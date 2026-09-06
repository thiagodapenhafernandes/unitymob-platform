import { isWhatsAppTab } from "./security.js";

export async function openWhatsApp(windowId) {
  const tabs = await chrome.tabs.query({ windowId, url: "https://web.whatsapp.com/*" });
  if (tabs.length) return chrome.tabs.update((tabs.find(tab => tab.active) || tabs[0]).id, { active: true });
  const tab = await chrome.tabs.create({ windowId, url: "https://web.whatsapp.com/", active: true });
  return { ...tab, url: "https://web.whatsapp.com/" };
}

export async function configurePanel(tab) {
  if (!Number.isInteger(tab?.id)) return;
  await chrome.sidePanel.setOptions({ tabId: tab.id, path: "panel.html", enabled: isWhatsAppTab(tab) });
}

export async function openFromToolbar(tab) {
  const target = isWhatsAppTab(tab) ? tab : await openWhatsApp(tab.windowId);
  await configurePanel(target);
  await chrome.sidePanel.open({ tabId: target.id });
}
