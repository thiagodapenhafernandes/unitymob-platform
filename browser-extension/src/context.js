// Passed to chrome.scripting.executeScript in MAIN. Keep this function self-contained.
// Only a bounded projection leaves the page: never serialize ChatModel or messages.
export async function readWhatsAppContext() {
  const wpp = window.WPP;
  if (!wpp?.isReady) return { state: "loading" };
  if (wpp.version !== "4.6.0") return { state: "incompatible" };
  const idOf = value => typeof value === "string" ? value : value?._serialized || value?.toString?.() || "";
  try {
    const account = idOf(wpp.conn.getMyUserId());
    if (!account) return { state: "disconnected" };
    const chat = wpp.chat.getActiveChat();
    if (!chat) return { state: "no_chat", account };
    const chatId = idOf(chat.id);
    if (!chatId || chatId.length > 120) return { state: "unavailable" };
    if (!/@(c\.us|s\.whatsapp\.net|lid)$/.test(chatId)) return { state: "unsupported", account, chatId };
    const cleanName = value => {
      if (typeof value !== "string") return null;
      const name = value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 200);
      return name && !/^[+\d\s().-]+$/.test(name) ? name : null;
    };
    const bounded = async read => {
      let timeout;
      try {
        return await Promise.race([
          read(),
          new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error("timeout")), 2000); })
        ]);
      } catch { return null; }
      finally { clearTimeout(timeout); }
    };
    const [entry, contact] = await Promise.all([
      bounded(() => wpp.contact.getPnLidEntry(chat.id)),
      bounded(() => wpp.contact.get(chat.id))
    ]);
    const raw = entry?.phoneNumber?.id;
    const phone = typeof raw === "string" && /^\d{8,15}$/.test(raw) ? `+${raw}` : null;
    const name = [contact?.name, contact?.pushname, contact?.verifiedName, chat.formattedTitle]
      .map(cleanName).find(Boolean) || null;
    // Recheck after awaiting phone resolution: the user may have changed chats/accounts.
    if (idOf(wpp.conn.getMyUserId()) !== account || idOf(wpp.chat.getActiveChat()?.id) !== chatId) {
      return { state: "changed" };
    }
    return { state: "ready", account, chatId, phone, name };
  } catch { return { state: "unavailable" }; }
}

export function contextKey(context) {
  return JSON.stringify([context?.state, context?.account, context?.chatId, context?.phone]);
}

export function validateContext(context) {
  const states = ["loading", "incompatible", "disconnected", "no_chat", "unsupported", "unavailable", "changed", "ready"];
  if (!context || !states.includes(context.state)) throw new Error("invalid_context");
  for (const name of ["account", "chatId"]) {
    if (context[name] != null && (typeof context[name] !== "string" || context[name].length > 120)) throw new Error("invalid_context");
  }
  if (context.phone != null && !/^\+\d{8,15}$/.test(context.phone)) throw new Error("invalid_context");
  if (context.name != null && (typeof context.name !== "string" || context.name.length > 200 || /[\u0000-\u001f\u007f]/.test(context.name))) throw new Error("invalid_context");
  if (context.state === "ready" && (!context.account || !context.chatId)) throw new Error("invalid_context");
  return { state: context.state, account: context.account, chatId: context.chatId, phone: context.phone || null, name: context.name || null };
}

// Only a confirmed, bounded property message can be sent to the still-active individual chat.
export async function sendPropertyMessage(expected, text, preview = null) {
  const wpp = window.WPP;
  if (!/@(c\.us|s\.whatsapp\.net|lid)$/.test(expected.chatId || "")) return {error: "context_changed"};
  const idOf = value => typeof value === "string" ? value : value?._serialized || value?.toString?.() || "";
  if (!wpp?.isReady || wpp.version !== "4.6.0" ||
      idOf(wpp.conn.getMyUserId()) !== expected.account || idOf(wpp.chat.getActiveChat()?.id) !== expected.chatId) return {error: "context_changed"};
  if (typeof text !== "string" || !text.length || text.length > 10000) return {error: "invalid_fields"};
  let directMessage = null;
  if (preview?.thumbnail) {
    try {
      const linkUrl = new URL(preview.url);
      if (linkUrl.protocol !== "https:" || linkUrl.username || linkUrl.password || !text.includes(linkUrl.href)) return {error: "invalid_fields"};
      directMessage = {body: text, type: "chat", subtype: "url", canonicalUrl: preview.url, matchedText: preview.url,
        title: String(preview.title || "Imóvel").slice(0, 200), description: String(preview.description || "").slice(0, 200),
        doNotPlayInline: true, richPreviewType: 0, thumbnail: preview.thumbnail};
    } catch { return {error: "invalid_fields"}; }
  }
  if ((!directMessage && typeof wpp.chat.prepareLinkPreview !== "function") || typeof wpp.chat.sendRawMessage !== "function") return {error: "preview_unavailable"};
  let timer;
  let prepared;
  try {
    prepared = await Promise.race([
      directMessage ? Promise.resolve(directMessage) : wpp.chat.prepareLinkPreview({body: text, type: "chat", subtype: null, urlText: null, urlNumber: null}, {linkPreview: true}),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("preview_timeout")), 15000); })
    ]);
  } catch (error) { return {error: error.message === "preview_timeout" ? "preview_timeout" : "preview_unavailable"}; }
  finally { clearTimeout(timer); }
  // Preparation can finish after the user switches conversations. Never send to the old recipient.
  if (idOf(wpp.conn.getMyUserId()) !== expected.account || idOf(wpp.chat.getActiveChat()?.id) !== expected.chatId) return {error: "context_changed"};
  if (prepared?.subtype !== "url" || typeof prepared.thumbnail !== "string" || !prepared.thumbnail.length) return {error: "preview_unavailable"};
  // Same final step used by sendTextMessage, reusing the prepared image instead of fetching twice.
  try { await wpp.chat.sendRawMessage(expected.chatId, prepared, {createChat: false}); }
  catch { return {error: "send_unconfirmed"}; }
  return {sent: true};
}

// A real conversation change must always invalidate the previous recipient.
export function shouldReloadContext(changed, forced, editing) {
  return changed || (forced && !editing);
}
