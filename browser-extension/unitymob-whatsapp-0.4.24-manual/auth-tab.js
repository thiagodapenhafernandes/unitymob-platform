// Fallback for Chrome profiles that cannot display the identity auth window.
export function authorizeInTab(url, callbackUrl) {
  return new Promise((resolve, reject) => {
    let tabId;
    const expected = new URL(callbackUrl);
    const finish = (error, result) => {
      clearTimeout(timeout);
      chrome.tabs.onUpdated.removeListener(updated);
      chrome.tabs.onRemoved.removeListener(removed);
      if (error) reject(error); else resolve(result);
    };
    const updated = (id, change) => {
      if (id !== tabId || !change.url) return;
      let target;
      try { target = new URL(change.url); } catch { return; }
      if (target.origin !== expected.origin || target.pathname !== expected.pathname) return;
      finish(null, change.url);
      chrome.tabs.remove(tabId).catch(() => {});
    };
    const removed = id => { if (id === tabId) finish(new Error("login_cancelled")); };
    const timeout = setTimeout(() => finish(new Error("pairing_expired")), 5 * 60_000);
    chrome.tabs.onUpdated.addListener(updated);
    chrome.tabs.onRemoved.addListener(removed);
    chrome.tabs.create({ url, active: true }).then(tab => {
      tabId = tab.id;
      // A fast redirect can complete before create resolves.
      return chrome.tabs.get(tabId);
    }).then(tab => updated(tab.id, { url: tab.url })).catch(() => finish(new Error("login_window_failed")));
  });
}
