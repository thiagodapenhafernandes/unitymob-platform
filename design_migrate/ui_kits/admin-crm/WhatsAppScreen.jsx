// WhatsApp — atendimento inbox (conversation list + thread + context).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const convos = [
    { id: 1, name: "Marina Costa", last: "Perfeito, podemos agendar a visita?", time: "12:41", unread: 2, tag: { c: "red", t: "Quente" }, active: true },
    { id: 2, name: "Eduardo Lima", last: "Vou confirmar com o banco e retorno.", time: "12:08", unread: 0, tag: { c: "cyan", t: "Financiamento" } },
    { id: 3, name: "Patrícia Nunes", last: "Áudio · 0:42", time: "11:52", unread: 0, tag: null },
    { id: 4, name: "Rafael Souza", last: "Obrigado pelas fotos!", time: "10:30", unread: 0, tag: { c: "green", t: "Visita agendada" } },
    { id: 5, name: "Juliana Alves", last: "Qual o valor do condomínio?", time: "Ontem", unread: 0, tag: null },
  ];

  const thread = [
    { from: "them", text: "Oi! Vi o anúncio do apartamento na Vila Mariana. Ainda está disponível?", time: "12:18" },
    { from: "me", text: "Olá, Marina! Está sim 😊 Apto de 2 quartos, 68m², R$ 680 mil. Quer que eu envie mais fotos?", time: "12:20" },
    { from: "them", text: "Quero sim, por favor!", time: "12:22" },
    { from: "me", text: "📎 apto-302-vila-mariana.pdf", time: "12:24", doc: true },
    { from: "them", text: "Perfeito, podemos agendar a visita?", time: "12:41" },
  ];

  function Convo({ c }) {
    return (
      <div style={{ display: "flex", gap: 10, padding: "10px 12px", cursor: "pointer", borderLeft: `2px solid ${c.active ? "var(--entity-whatsapp)" : "transparent"}`, background: c.active ? "var(--surface-soft)" : "transparent" }}>
        <span className="ax-avatar" style={{ width: 38, height: 38, flex: "none", background: "#dcf5ee", color: "var(--entity-whatsapp)" }}>{c.name.split(" ").map((n) => n[0]).slice(0, 2).join("")}</span>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
            <strong style={{ fontSize: 13, color: "var(--ink)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.name}</strong>
            <span style={{ fontSize: 11, color: "var(--ink-faint)", flex: "none" }}>{c.time}</span>
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 8, marginTop: 2 }}>
            <span style={{ fontSize: 12, color: "var(--ink-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.last}</span>
            {c.unread > 0 && <span style={{ flex: "none", minWidth: 18, height: 18, borderRadius: 999, background: "var(--entity-whatsapp)", color: "#fff", fontSize: 11, fontWeight: 700, display: "grid", placeItems: "center", padding: "0 5px" }}>{c.unread}</span>}
          </div>
          {c.tag && <div style={{ marginTop: 5 }}><UM.LeadLabelChip color={c.tag.c}>{c.tag.t}</UM.LeadLabelChip></div>}
        </div>
      </div>
    );
  }

  function WhatsApp() {
    return (
      <section>
        <div className="ax-panel" style={{ overflow: "hidden", height: "calc(100vh - var(--navbar-h) - var(--contextbar-h) - 24px)", display: "grid", gridTemplateColumns: "320px minmax(0,1fr) 280px" }}>
          {/* Conversation list */}
          <div style={{ borderRight: "1px solid var(--line-soft)", display: "flex", flexDirection: "column", minHeight: 0 }}>
            <div style={{ padding: 10, borderBottom: "1px solid var(--line-soft)" }}>
              <UM.SearchInput placeholder="Buscar conversa…" style={{ width: "100%", maxWidth: "none" }} />
            </div>
            <div style={{ overflowY: "auto" }}>
              {convos.map((c) => <Convo key={c.id} c={c} />)}
            </div>
          </div>

          {/* Thread */}
          <div style={{ display: "flex", flexDirection: "column", minHeight: 0, background: "#f4f1ea" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "9px 14px", borderBottom: "1px solid var(--line-soft)", background: "#fff" }}>
              <span className="ax-avatar" style={{ width: 34, height: 34, background: "#dcf5ee", color: "var(--entity-whatsapp)" }}>MC</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <strong style={{ fontSize: 13.5, color: "var(--ink)" }}>Marina Costa</strong>
                <div style={{ fontSize: 11.5, color: "var(--entity-whatsapp)" }}><i className="bi bi-circle-fill" style={{ fontSize: 7, marginRight: 4 }}></i>online</div>
              </div>
              <UM.Badge tone="green" dot>Ativo</UM.Badge>
              <button className="ax-ico-btn"><i className="bi bi-telephone"></i></button>
              <button className="ax-ico-btn"><i className="bi bi-three-dots-vertical"></i></button>
            </div>
            <div style={{ flex: 1, overflowY: "auto", padding: 16, display: "flex", flexDirection: "column", gap: 8 }}>
              {thread.map((m, i) => (
                <div key={i} style={{ alignSelf: m.from === "me" ? "flex-end" : "flex-start", maxWidth: "72%", padding: "8px 11px", borderRadius: 10, fontSize: 13, lineHeight: 1.4, background: m.from === "me" ? "#d9fdd3" : "#fff", color: "var(--ink)", boxShadow: "0 1px 1px rgba(15,23,42,.08)" }}>
                  {m.doc && <i className="bi bi-file-earmark-pdf" style={{ marginRight: 6, color: "var(--danger)" }}></i>}
                  {m.text}
                  <div style={{ fontSize: 10, color: "var(--ink-faint)", textAlign: "right", marginTop: 3 }}>{m.time} {m.from === "me" && <i className="bi bi-check2-all" style={{ color: "#53bdeb" }}></i>}</div>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 8, padding: 10, borderTop: "1px solid var(--line-soft)", background: "#fff" }}>
              <button className="ax-ico-btn"><i className="bi bi-paperclip"></i></button>
              <input className="ax-input" placeholder="Digite uma mensagem…" style={{ flex: 1 }} />
              <UM.Button variant="primary" icon="send">Enviar</UM.Button>
            </div>
          </div>

          {/* Context panel */}
          <div style={{ borderLeft: "1px solid var(--line-soft)", padding: 14, overflowY: "auto", display: "grid", gap: 12, alignContent: "start" }}>
            <div style={{ textAlign: "center", display: "grid", gap: 6, justifyItems: "center", paddingBottom: 12, borderBottom: "1px solid var(--line-soft)" }}>
              <span className="ax-avatar" style={{ width: 52, height: 52, fontSize: 18, background: "#dcf5ee", color: "var(--entity-whatsapp)" }}>MC</span>
              <strong style={{ fontSize: 14, color: "var(--ink)" }}>Marina Costa</strong>
              <span style={{ fontSize: 12, color: "var(--ink-muted)" }}>+55 11 98765-4321</span>
            </div>
            <div>
              <span className="ax-eyebrow" style={{ marginBottom: 6 }}>Lead vinculado</span>
              <UM.ContextPin type="lead">Marina Costa · Novo</UM.ContextPin>
            </div>
            <div>
              <span className="ax-eyebrow" style={{ marginBottom: 6 }}>Imóvel de interesse</span>
              <UM.ContextPin type="property">Apto 302 · Vila Mariana</UM.ContextPin>
            </div>
            <div>
              <span className="ax-eyebrow" style={{ marginBottom: 6 }}>Etiquetas</span>
              <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
                <UM.LeadLabelChip color="red">Quente</UM.LeadLabelChip>
                <UM.LeadLabelChip color="green">Visita agendada</UM.LeadLabelChip>
              </div>
            </div>
            <UM.Button block icon="calendar-event">Agendar visita</UM.Button>
          </div>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.whatsapp = WhatsApp;
})();
