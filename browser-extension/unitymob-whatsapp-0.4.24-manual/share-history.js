// Counts only confirmed sends from this installation. Caller serializes writes.
export async function shareHistoryKey(connection, context, leadId) {
  const scope = JSON.stringify([connection.origin, connection.account?.tenant_id || connection.tenantId || connection.token, context.account, context.chatId, String(leadId)]);
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(scope));
  return "propertyShares:" + Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2,"0")).join("");
}
export async function readShareHistory(key) {
  return (await chrome.storage.local.get(key))[key] || {};
}
export async function recordPropertyShare(key, propertyId) {
  const history = await readShareHistory(key);
  const previous = history[propertyId]?.count;
  const record = {count: (Number.isSafeInteger(previous) && previous > 0 ? previous : 0) + 1, last_sent_at: new Date().toISOString()};
  history[propertyId] = record;
  await chrome.storage.local.set({[key]:history});
  return record;
}
