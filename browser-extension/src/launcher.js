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
  // Open before any await: Chrome requires the original toolbar user gesture.
  const panel = chrome.sidePanel.open({ windowId: tab.windowId });
  await Promise.all([panel, isWhatsAppTab(tab) ? Promise.resolve(tab) : openWhatsApp(tab.windowId)]);
}
