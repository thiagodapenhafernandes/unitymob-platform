import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { allowedOrigin, isWhatsAppTab, isPanelSender, createPairing, leadId } from "../src/security.js";

test("accepts only an exact approved origin and loopback-only development HTTP", () => {
  const valid = "https://app.conexaobc.com";
  assert.equal(allowedOrigin(valid, [valid]), valid);
  for (const origin of ["https://app.conexaobc.com.evil.test", "https://evil.test", "https://user:password@app.conexaobc.com", "https://app.conexaobc.com/path"]) {
    assert.throws(() => allowedOrigin(origin, [valid]));
  }
  assert.throws(() => allowedOrigin("http://app.conexaobc.com", ["http://app.conexaobc.com"]));
  assert.equal(allowedOrigin("http://localhost:3021", ["http://localhost:3021"]), "http://localhost:3021");
});

test("rejects page/content-script senders even with a known extension ID", () => {
  const runtime = { id: "test", getURL: name => `chrome-extension://test/${name}` };
  assert.ok(isPanelSender({ id: "test", url: runtime.getURL("panel.html") }, runtime));
  assert.ok(!isPanelSender({ id: "test", url: "https://web.whatsapp.com/", tab: { id: 1 } }, runtime));
  assert.ok(!isPanelSender({ id: "test", url: runtime.getURL("panel.html"), tab: { id: 1 } }, runtime));
  assert.ok(!isPanelSender({ id: "other", url: runtime.getURL("panel.html") }, runtime));
  assert.ok(!isWhatsAppTab({ url: "https://web.whatsapp.com.evil.test/" }));
  assert.ok(isWhatsAppTab({ url: "https://web.whatsapp.com/" }));
});

test("pairing has a random verifier and only a SHA-256 challenge for the authorization URL", async () => {
  const first = await createPairing(); const second = await createPairing();
  assert.match(first.verifier, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(first.challenge, createHash("sha256").update(first.verifier).digest("hex"));
  assert.notEqual(first.verifier, second.verifier);
  assert.throws(() => leadId("../../session"));
  assert.equal(leadId(42), 42);
});
