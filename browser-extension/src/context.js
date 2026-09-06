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
