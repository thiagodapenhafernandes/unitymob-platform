import test from "node:test";
import assert from "node:assert/strict";
import { readWhatsAppContext, sendPropertyMessage, validateContext, contextKey } from "../src/context.js";

function fixture({ chatId = "5511999999999@c.us", phone = "5511999999999", contact = { name: "Contato salvo", pushname: "Perfil" }, resolve } = {}) {
  const wpp = {
    version: "4.6.0", isReady: true,
    conn: { getMyUserId: () => ({ _serialized: "5548999999999@c.us" }) },
    chat: { getActiveChat: () => ({ id: { _serialized: chatId }, msgs: [{ body: "Must never leave the page" }] }) },
    contact: { get: async () => contact, getPnLidEntry: resolve || (async () => ({ phoneNumber: { id: phone } })) }
  };
  global.window = { WPP: wpp };
  return wpp;
}

test("projects only identity, without serializing messages or contact object", async () => {
  fixture();
  assert.deepEqual(await readWhatsAppContext(), { state: "ready", account: "5548999999999@c.us", chatId: "5511999999999@c.us", phone: "+5511999999999", name: "Contato salvo" });
});

test("resolves LID separately; never treats it as a phone number", async () => {
  fixture({ chatId: "987654321@lid" });
  assert.equal((await readWhatsAppContext()).phone, "+5511999999999");
  fixture({ chatId: "987654321@lid", resolve: async () => { throw new Error("unresolved"); } });
  assert.equal((await readWhatsAppContext()).phone, null);
});

test("does not resolve groups, newsletters or status", async () => {
  for (const chatId of ["123@g.us", "123@newsletter", "status@broadcast"]) {
    fixture({ chatId, resolve: () => assert.fail("must not read a group") });
    assert.equal((await readWhatsAppContext()).state, "unsupported");
  }
});

test("discards a response when chat or account changes during phone lookup", async () => {
  for (const kind of ["chat", "account"]) {
    let done;
    const wpp = fixture({ resolve: () => new Promise(resolve => { done = resolve; }) });
    const pending = readWhatsAppContext();
    if (kind === "chat") wpp.chat.getActiveChat = () => ({ id: "5511888888888@c.us" });
    else wpp.conn.getMyUserId = () => "5548777777777@c.us";
    done({ phoneNumber: { id: "5511999999999" } });
    assert.equal((await pending).state, "changed");
  }
});

test("handles logout, no chat and unsupported library without exceptions", async () => {
  const wpp = fixture(); wpp.conn.getMyUserId = () => undefined;
  assert.equal((await readWhatsAppContext()).state, "disconnected");
  fixture().chat.getActiveChat = () => undefined;
  assert.equal((await readWhatsAppContext()).state, "no_chat");
  fixture().version = "0.0.0";
  assert.equal((await readWhatsAppContext()).state, "incompatible");
  window.WPP = undefined;
  assert.equal((await readWhatsAppContext()).state, "loading");
});

test("validates untrusted projections and identifies different account/chat contexts", () => {
  assert.throws(() => validateContext({ state: "ready" }));
  assert.throws(() => validateContext({ state: "no_chat", account: {} }));
  assert.throws(() => validateContext({ state: "ready", account: "a", chatId: "b", phone: "<script>" }));
  assert.notEqual(contextKey({ account: "a", chatId: "b" }), contextKey({ account: "c", chatId: "b" }));
});


test("uses profile name as fallback and sanitizes bounded names", async () => {
  fixture({ contact: { name: "  ", pushname: "  Maria\nSilva  " } });
  assert.equal((await readWhatsAppContext()).name, "Maria Silva");
  fixture({ contact: { name: "x".repeat(250) } });
  assert.equal((await readWhatsAppContext()).name.length, 200);
  fixture({ contact: { name: "+55 (11) 99999-9999", pushname: {} } });
  assert.equal((await readWhatsAppContext()).name, null);
});

test("contact lookup failure preserves the resolved phone", async () => {
  fixture().contact.get = async () => { throw new Error("unavailable"); };
  const result = await readWhatsAppContext();
  assert.equal(result.phone, "+5511999999999");
  assert.equal(result.name, null);
});

test("discards contact name when conversation changes while awaiting it", async () => {
  let done;
  const wpp = fixture();
  wpp.contact.get = () => new Promise(resolve => { done = resolve; });
  const pending = readWhatsAppContext();
  wpp.chat.getActiveChat = () => ({ id: "other@c.us" });
  done({ name: "Previous contact" });
  assert.equal((await pending).state, "changed");
});

test("name metadata does not reset the conversation identity; invalid names are rejected", () => {
  const context = { state: "ready", account: "a", chatId: "b", name: "Maria" };
  assert.equal(contextKey(context), contextKey({ ...context, name: "Updated" }));
  for (const name of [{}, "x".repeat(201), "bad\nname"]) {
    assert.throws(() => validateContext({ ...context, name }));
  }
});

test("property sending targets only the unchanged individual conversation", async () => {
  const wpp = fixture();
  let sends = 0;
  wpp.chat.sendTextMessage = async (id, text) => { sends++; assert.equal(id, "5511999999999@c.us"); assert.equal(text, "Imóvel 8334"); };
  const expected = await readWhatsAppContext();
  assert.deepEqual(await sendPropertyMessage(expected, "Imóvel 8334"), {sent: true});
  wpp.chat.getActiveChat = () => ({id: "other@c.us"});
  assert.deepEqual(await sendPropertyMessage(expected, "Imóvel 8334"), {error: "context_changed"});
  assert.equal(sends, 1);
});
