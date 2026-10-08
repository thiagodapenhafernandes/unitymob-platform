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

// Chrome retains the click gesture through API callbacks, not arbitrary async work.
export function openFromToolbar(tab) {
  return new Promise((resolve, reject) => {
    const failed = () => {
      const error = chrome.runtime.lastError;
      if (error) reject(new Error(error.message));
      return !!error;
    };
    const open = target => {
      chrome.sidePanel.setOptions({ tabId: target.id, path: "panel.html", enabled: true }, () => {
        if (failed()) return;
        chrome.sidePanel.open({ tabId: target.id }, () => {
          if (!failed()) resolve();
        });
      });
    };
    if (isWhatsAppTab(tab)) return open(tab);
    chrome.tabs.query({ windowId: tab.windowId, url: "https://web.whatsapp.com/*" }, tabs => {
      if (failed()) return;
      const target = tabs.find(item => item.active) || tabs[0];
      if (target) {
        chrome.tabs.update(target.id, { active: true }, updated => {
          if (!failed()) open(updated);
        });
      } else {
        chrome.tabs.create({ windowId: tab.windowId, url: "https://web.whatsapp.com/", active: true }, created => {
          if (!failed()) open(created);
        });
      }
    });
  });
}
