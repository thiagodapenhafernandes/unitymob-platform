import { readFile } from "node:fs/promises"
import test from "node:test"
import assert from "node:assert/strict"
const source = (await readFile(new URL("../../app/javascript/controllers/ax_lead_message_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
const { default: LeadMessage } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

test("atualiza somente o lead correto e leitura antiga não apaga mensagem mais nova", () => {
  const row = new LeadMessage()
  row.leadIdValue = 12
  row.cursorValue = 5
  row.noticeTarget = { hidden: true }
  row.previewTarget = { textContent: "" }
  row.update({ detail: { lead_id: 13, kind: "instagram_message", instagram_message_id: 8, body: "Outra pessoa" } })
  assert.equal(row.noticeTarget.hidden, true)
  row.update({ detail: { lead_id: 12, kind: "instagram_message", instagram_message_id: 8, body: "<script>texto</script>" } })
  assert.equal(row.noticeTarget.hidden, false)
  assert.equal(row.previewTarget.textContent, "<script>texto</script>")
  row.update({ detail: { lead_id: 12, kind: "instagram_message", instagram_message_id: 6, body: "Evento antigo" } })
  assert.equal(row.cursorValue, 8)
  assert.equal(row.previewTarget.textContent, "<script>texto</script>")
  row.update({ detail: { lead_id: 12, event: "unread_changed", cursor: 7 } })
  assert.equal(row.noticeTarget.hidden, false)
  row.update({ detail: { lead_id: 12, event: "unread_changed", cursor: 8 } })
  assert.equal(row.noticeTarget.hidden, true)
})
