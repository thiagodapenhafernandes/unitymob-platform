// Unitymob Admin CRM — consolidated app for the DC template.
// Reads design-system components from the global namespace (loaded via ds-base.js).
const NS = "UnitymobDesignSystem_2a309d";

function AdminApp() {
  // Wait until the design-system bundle has registered on window.
  const [ready, setReady] = React.useState(!!window[NS]);
  React.useEffect(() => {
    if (window[NS]) return;
    const t = setInterval(() => {
      if (window[NS]) { setReady(true); clearInterval(t); }
    }, 60);
    return () => clearInterval(t);
  }, []);
  const [current, setCurrent] = React.useState("dashboard");

  if (!ready) {
    return React.createElement("div", { style: { padding: 40, color: "#697586", fontFamily: "Inter, sans-serif" } }, "Carregando…");
  }
  const UM = window[NS];

  // ---------- shared bits ----------
  const initials = (name) => name.split(" ").map((n) => n[0]).slice(0, 2).join("");

  const NAV = [
    { section: "Produto" },
    { id: "dashboard", icon: "speedometer2", label: "Painel" },
    { id: "imoveis", icon: "houses", label: "Imóveis" },
    { id: "leads", icon: "person-badge", label: "Leads" },
    { section: "Operação" },
    { id: "whatsapp", icon: "whatsapp", label: "WhatsApp" },
    { id: "automacao", icon: "lightning-charge", label: "Automação" },
    { id: "distribuicao", icon: "diagram-3", label: "Distribuição de Leads" },
    { id: "captacoes", icon: "journal-plus", label: "Captações" },
    { section: "Gestão" },
    { id: "proprietarios", icon: "person-vcard", label: "Proprietários" },
    { id: "lojas", icon: "shop", label: "Lojas" },
    { id: "usuarios", icon: "people", label: "Usuários" },
    { section: "Crescimento" },
    { id: "marketing", icon: "megaphone", label: "Marketing" },
  ];
  const CONTEXT = {
    dashboard: { crumb: ["Painel"], title: "Painel" },
    imoveis: { crumb: ["Imóveis"], title: "Imóveis" },
    leads: { crumb: ["Comercial", "Funil de Leads"], title: "Leads" },
    whatsapp: { crumb: ["WhatsApp", "Atendimento"], title: "WhatsApp" },
    automacao: { crumb: ["Automação"], title: "Automação" },
    distribuicao: { crumb: ["Distribuição de Leads"], title: "Distribuição" },
    captacoes: { crumb: ["Captações"], title: "Captações" },
    proprietarios: { crumb: ["Proprietários"], title: "Proprietários" },
    lojas: { crumb: ["Lojas"], title: "Lojas" },
    usuarios: { crumb: ["Usuários"], title: "Usuários" },
    marketing: { crumb: ["Marketing"], title: "Marketing" },
  };

  // ---------- Dashboard ----------
  function Dashboard() {
    const bars = [42, 58, 51, 67, 60, 78, 71, 84, 76, 90, 82, 128];
    const funnel = [
      { label: "Novos", value: 128, pct: 100 },
      { label: "Em atendimento", value: 74, pct: 58 },
      { label: "Visita agendada", value: 39, pct: 30 },
      { label: "Proposta", value: 18, pct: 14 },
      { label: "Fechado", value: 9, pct: 7 },
    ];
    const pend = [
      { icon: "file-earmark-text", label: "Captações em rascunho", count: 6, tone: "amber" },
      { icon: "hourglass-split", label: "Leads represados", count: 9, tone: "red" },
      { icon: "hand-index-thumb", label: "Pedidos manuais pendentes", count: 3, tone: "amber" },
      { icon: "exclamation-triangle-fill", label: "Imóveis com erro de sync", count: 4, tone: "red" },
    ];
    const brokers = [
      { name: "Rafael Menezes", loja: "Centro", val: 14 },
      { name: "Bianca Toledo", loja: "Zona Sul", val: 11 },
      { name: "Diego Farias", loja: "Centro", val: 9 },
      { name: "Camila Prado", loja: "Litoral", val: 7 },
    ];
    return (
      <section>
        <header className="ax-dashboard-command">
          <div>
            <span className="ax-eyebrow">Cockpit operacional</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3 }}>
              <h1>Boa tarde, Marina</h1>
              <UM.Badge tone="blue">Admin</UM.Badge>
            </div>
            <p>terça-feira, 1 de julho · Campo ativo: 3 check-ins agora, 128 leads hoje.</p>
          </div>
          <div className="ax-dashboard-command__status"><i className="bi bi-hdd-network"></i> Operação</div>
          <UM.Badge tone="green" dot>Campo ativo</UM.Badge>
        </header>
        <div className="ax-dashboard-kpis">
          <UM.MetricCard label="Imóveis no catálogo" value="1.284" badge={<UM.Badge tone="green" dot>Ativos</UM.Badge>} hint="86 destaques · 12 empreendimentos" />
          <UM.MetricCard label="Leads hoje" value="128" badge={<UM.Badge tone="gray">+312 em 7d</UM.Badge>} hint="9 represados · 22 novos" />
          <UM.MetricCard label="Check-ins ativos" value="3" badge={<UM.Badge tone="green" dot>Ao vivo</UM.Badge>} hint="18 hoje · 1 suspeito" />
          <UM.MetricCard label="Regras de distribuição" value="8/12" badge={<UM.Badge tone="blue">4 c/ check-in</UM.Badge>} progress={66} />
        </div>
        <div className="ax-grid" style={{ gridTemplateColumns: "minmax(0,1.6fr) minmax(0,1fr)", marginBottom: 12 }}>
          <div className="ax-panel">
            <div className="ax-panel__head">
              <div><span className="ax-eyebrow">Aquisição</span><div className="ax-panel__title">Leads — últimos 30 dias</div></div>
              <UM.Badge tone="green" dot>+18% vs. mês anterior</UM.Badge>
            </div>
            <div style={{ padding: 16 }}>
              <div style={{ display: "flex", alignItems: "flex-end", gap: 6, height: 168 }}>
                {bars.map((b, i) => (
                  <div key={i} style={{ flex: 1, height: `${(b / 128) * 100}%`, background: i === bars.length - 1 ? "var(--primary)" : "var(--primary-soft)", borderRadius: "5px 5px 0 0", minHeight: 6 }} />
                ))}
              </div>
            </div>
          </div>
          <div className="ax-panel">
            <div className="ax-panel__head"><div><span className="ax-eyebrow">Funil</span><div className="ax-panel__title">Conversão comercial</div></div></div>
            <div style={{ padding: "14px 16px", display: "grid", gap: 12 }}>
              {funnel.map((f) => (
                <div key={f.label}>
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12.5, marginBottom: 4 }}>
                    <span style={{ color: "var(--ink-body)" }}>{f.label}</span>
                    <strong className="ax-num" style={{ color: "var(--ink)" }}>{f.value}</strong>
                  </div>
                  <div className="ax-progress"><i style={{ width: `${f.pct}%` }} /></div>
                </div>
              ))}
            </div>
          </div>
        </div>
        <div className="ax-grid" style={{ gridTemplateColumns: "minmax(0,1fr) minmax(0,1.2fr)" }}>
          <div className="ax-panel">
            <div className="ax-panel__head"><div><span className="ax-eyebrow">Hoje</span><div className="ax-panel__title">Pendências</div></div><UM.Badge tone="amber">4 pend.</UM.Badge></div>
            <div style={{ padding: 10, display: "grid", gap: 6 }}>
              {pend.map((p) => (
                <a key={p.label} href="#" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "9px 10px", border: "1px solid var(--line)", borderRadius: 8, background: "var(--surface-soft)", color: "var(--ink-body)", fontSize: 12.5 }}>
                  <span><i className={`bi bi-${p.icon}`} style={{ marginRight: 8, color: "var(--ink-muted)" }}></i>{p.label}</span>
                  <UM.Badge tone={p.tone}>{p.count}</UM.Badge>
                </a>
              ))}
            </div>
          </div>
          <div className="ax-panel">
            <div className="ax-panel__head"><div><span className="ax-eyebrow">Performance</span><div className="ax-panel__title">Top corretores</div></div><a href="#" style={{ fontSize: 12, color: "var(--primary)" }}>Ver todos</a></div>
            <table className="ax-table">
              <thead><tr><th>Corretor</th><th>Loja</th><th style={{ textAlign: "right" }}>Fechados</th></tr></thead>
              <tbody>
                {brokers.map((b) => (
                  <tr key={b.name}>
                    <td><span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}><span className="ax-avatar" style={{ width: 24, height: 24, fontSize: 11 }}>{initials(b.name)}</span><span className="ax-strong">{b.name}</span></span></td>
                    <td>{b.loja}</td>
                    <td className="ax-num" style={{ textAlign: "right" }}><strong style={{ color: "var(--ink)" }}>{b.val}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    );
  }

  // ---------- Leads ----------
  function Leads() {
    const COLUMNS = [
      { key: "novo", eyebrow: "Entrada", title: "Novos", cards: [
        { name: "Marina Costa", origem: "Portal ZAP", imovel: "Apto 2Q · Vila Mariana", valor: "R$ 680 mil", labels: [{ c: "red", t: "Quente" }], time: "12 min" },
        { name: "Eduardo Lima", origem: "Meta Ads", imovel: "Cobertura · Moema", valor: "R$ 1,9 mi", labels: [{ c: "cyan", t: "Financiamento" }], time: "38 min" },
        { name: "Patrícia Nunes", origem: "WhatsApp", imovel: "Casa 3Q · Granja", valor: "R$ 920 mil", labels: [], time: "1 h" },
      ] },
      { key: "atendimento", eyebrow: "Comercial", title: "Em atendimento", cards: [
        { name: "Rafael Souza", origem: "Indicação", imovel: "Studio · Centro", valor: "R$ 340 mil", labels: [{ c: "amber", t: "Retornar" }], time: "3 h" },
        { name: "Juliana Alves", origem: "Portal OLX", imovel: "Apto 3Q · Tatuapé", valor: "R$ 750 mil", labels: [{ c: "green", t: "Visita agendada" }], time: "5 h" },
      ] },
      { key: "proposta", eyebrow: "Negociação", title: "Proposta", cards: [
        { name: "Carlos Prado", origem: "Site", imovel: "Casa · Alphaville", valor: "R$ 2,4 mi", labels: [{ c: "purple", t: "Proposta enviada" }], time: "1 d" },
      ] },
      { key: "fechado", eyebrow: "Ganho", title: "Fechado", cards: [
        { name: "Beatriz Rocha", origem: "Portal ZAP", imovel: "Apto 2Q · Pinheiros", valor: "R$ 890 mil", labels: [{ c: "green", t: "Contrato" }], time: "2 d" },
      ] },
    ];
    const LeadCard = ({ c }) => (
      <article className="ax-board__card">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 8, minWidth: 0 }}>
            <span className="ax-avatar" style={{ width: 26, height: 26, fontSize: 11 }}>{initials(c.name)}</span>
            <strong style={{ fontSize: 13, color: "var(--ink)" }}>{c.name}</strong>
          </span>
          <button className="ax-ico-btn" aria-label="Mais"><i className="bi bi-three-dots-vertical"></i></button>
        </div>
        <div style={{ fontSize: 12, color: "var(--ink-body)" }}><i className="bi bi-house-door" style={{ color: "var(--ink-faint)", marginRight: 5 }}></i>{c.imovel}</div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <strong className="ax-num" style={{ fontSize: 13, color: "var(--ink)" }}>{c.valor}</strong>
          <span className="ax-badge ax-badge--gray" style={{ fontSize: 10.5 }}><i className="bi bi-broadcast-pin" style={{ fontSize: 11 }}></i>{c.origem}</span>
        </div>
        {c.labels.length > 0 && <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>{c.labels.map((l, i) => <UM.LeadLabelChip key={i} color={l.c}>{l.t}</UM.LeadLabelChip>)}</div>}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", borderTop: "1px solid var(--line-soft)", paddingTop: 8, fontSize: 11, color: "var(--ink-muted)" }}>
          <span><i className="bi bi-clock" style={{ marginRight: 4 }}></i>{c.time}</span>
          <span style={{ display: "inline-flex", gap: 6 }}><i className="bi bi-whatsapp" style={{ color: "var(--entity-whatsapp)" }}></i><i className="bi bi-telephone"></i><i className="bi bi-calendar-event"></i></span>
        </div>
      </article>
    );
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div><span className="ax-eyebrow">Comercial</span><h1 style={{ marginTop: 3 }}>Funil de Leads</h1><p>231 leads ativos · atualizado agora</p></div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="funnel">Filtros</UM.Button>
            <UM.Button size="sm" icon="download">Exportar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg">Novo lead</UM.Button>
          </div>
        </div>
        <div className="ax-board">
          {COLUMNS.map((col) => (
            <div key={col.key} className="ax-board__column">
              <div className="ax-board__col-head">
                <div><span className="ax-board__col-eyebrow">{col.eyebrow}</span><span className="ax-board__col-title">{col.title}</span></div>
                <span className="ax-board__col-count">{col.cards.length}</span>
              </div>
              <div className="ax-board__col-body">{col.cards.map((c, i) => <LeadCard key={i} c={c} />)}</div>
            </div>
          ))}
        </div>
      </section>
    );
  }

  // ---------- WhatsApp ----------
  function WhatsApp() {
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
    const Convo = ({ c }) => (
      <div style={{ display: "flex", gap: 10, padding: "10px 12px", cursor: "pointer", borderLeft: `2px solid ${c.active ? "var(--entity-whatsapp)" : "transparent"}`, background: c.active ? "var(--surface-soft)" : "transparent" }}>
        <span className="ax-avatar" style={{ width: 38, height: 38, flex: "none", background: "#dcf5ee", color: "var(--entity-whatsapp)" }}>{initials(c.name)}</span>
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
    return (
      <section>
        <div className="ax-panel" style={{ overflow: "hidden", height: "calc(100vh - var(--navbar-h) - var(--contextbar-h) - 24px)", display: "grid", gridTemplateColumns: "320px minmax(0,1fr) 280px" }}>
          <div style={{ borderRight: "1px solid var(--line-soft)", display: "flex", flexDirection: "column", minHeight: 0 }}>
            <div style={{ padding: 10, borderBottom: "1px solid var(--line-soft)" }}><UM.SearchInput placeholder="Buscar conversa…" style={{ width: "100%", maxWidth: "none" }} /></div>
            <div style={{ overflowY: "auto" }}>{convos.map((c) => <Convo key={c.id} c={c} />)}</div>
          </div>
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
          <div style={{ borderLeft: "1px solid var(--line-soft)", padding: 14, overflowY: "auto", display: "grid", gap: 12, alignContent: "start" }}>
            <div style={{ textAlign: "center", display: "grid", gap: 6, justifyItems: "center", paddingBottom: 12, borderBottom: "1px solid var(--line-soft)" }}>
              <span className="ax-avatar" style={{ width: 52, height: 52, fontSize: 18, background: "#dcf5ee", color: "var(--entity-whatsapp)" }}>MC</span>
              <strong style={{ fontSize: 14, color: "var(--ink)" }}>Marina Costa</strong>
              <span style={{ fontSize: 12, color: "var(--ink-muted)" }}>+55 11 98765-4321</span>
            </div>
            <div><span className="ax-eyebrow" style={{ marginBottom: 6 }}>Lead vinculado</span><UM.ContextPin type="lead">Marina Costa · Novo</UM.ContextPin></div>
            <div><span className="ax-eyebrow" style={{ marginBottom: 6 }}>Imóvel de interesse</span><UM.ContextPin type="property">Apto 302 · Vila Mariana</UM.ContextPin></div>
            <div><span className="ax-eyebrow" style={{ marginBottom: 6 }}>Etiquetas</span><div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}><UM.LeadLabelChip color="red">Quente</UM.LeadLabelChip><UM.LeadLabelChip color="green">Visita agendada</UM.LeadLabelChip></div></div>
            <UM.Button block icon="calendar-event">Agendar visita</UM.Button>
          </div>
        </div>
      </section>
    );
  }

  // ---------- Imóveis ----------
  function Imoveis() {
    const rows = [
      { code: "COD-84213", title: "Apartamento 2Q · Vila Mariana", tipo: "Apartamento", bairro: "Vila Mariana", preco: "R$ 680.000", trans: "Venda", status: { c: "green", t: "Publicado", dot: true }, corretor: "Rafael M.", dorm: 2, banho: 2, vaga: 1, area: "68 m²" },
      { code: "COD-84117", title: "Cobertura Duplex · Moema", tipo: "Cobertura", bairro: "Moema", preco: "R$ 1.900.000", trans: "Venda", status: { c: "green", t: "Publicado", dot: true }, corretor: "Bianca T.", dorm: 3, banho: 4, vaga: 3, area: "180 m²" },
      { code: "COD-83998", title: "Casa Térrea 3Q · Granja Viana", tipo: "Casa", bairro: "Granja Viana", preco: "R$ 920.000", trans: "Venda", status: { c: "amber", t: "Em revisão" }, corretor: "Diego F.", dorm: 3, banho: 3, vaga: 4, area: "210 m²" },
      { code: "COD-83820", title: "Studio Mobiliado · Centro", tipo: "Studio", bairro: "Centro", preco: "R$ 2.400 / mês", trans: "Locação", status: { c: "blue", t: "Novo" }, corretor: "Camila P.", dorm: 1, banho: 1, vaga: 0, area: "32 m²" },
      { code: "COD-83714", title: "Apartamento 3Q · Tatuapé", tipo: "Apartamento", bairro: "Tatuapé", preco: "R$ 750.000", trans: "Venda", status: { c: "red", t: "Erro sync" }, corretor: "Rafael M.", dorm: 3, banho: 2, vaga: 2, area: "92 m²" },
      { code: "COD-83590", title: "Casa Condomínio · Alphaville", tipo: "Casa", bairro: "Alphaville", preco: "R$ 2.400.000", trans: "Venda", status: { c: "gray", t: "Rascunho" }, corretor: "Bianca T.", dorm: 4, banho: 5, vaga: 4, area: "340 m²" },
    ];
    const chips = ["Todos", "Venda", "Locação", "Destaques", "Publicados", "Em revisão", "Com erro"];
    const [chip, setChip] = React.useState("Todos");
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div><span className="ax-eyebrow">Catálogo</span><h1 style={{ marginTop: 3 }}>Imóveis</h1><p>1.284 imóveis · 86 destaques · sincronizado há 6 min</p></div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="arrow-repeat">Sincronizar</UM.Button>
            <UM.Button size="sm" icon="download">Exportar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg">Novo imóvel</UM.Button>
          </div>
        </div>
        <div className="ax-panel">
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: 12, borderBottom: "1px solid var(--line-soft)", flexWrap: "wrap" }}>
            <UM.SearchInput placeholder="Buscar por código, título, endereço…" style={{ flex: "1 1 260px" }} />
            <UM.Button size="sm" icon="funnel">Filtros avançados</UM.Button>
            <UM.Button size="sm" icon="sliders">Colunas</UM.Button>
            <div className="ax-tabs" style={{ marginLeft: "auto" }}>
              <button className="ax-tab is-active"><i className="bi bi-list-ul"></i></button>
              <button className="ax-tab"><i className="bi bi-grid"></i></button>
              <button className="ax-tab"><i className="bi bi-geo-alt"></i></button>
            </div>
          </div>
          <div style={{ display: "flex", gap: 6, padding: "10px 12px", borderBottom: "1px solid var(--line-soft)", flexWrap: "wrap" }}>
            {chips.map((c) => <button key={c} onClick={() => setChip(c)} className={c === chip ? "ax-btn ax-btn--sm ax-btn--primary" : "ax-btn ax-btn--sm"}>{c}</button>)}
          </div>
          <table className="ax-table">
            <thead>
              <tr>
                <th style={{ width: 34 }}><input type="checkbox" /></th>
                <th>Imóvel</th><th>Tipo</th><th>Bairro</th><th>Config.</th>
                <th style={{ textAlign: "right" }}>Preço</th><th>Status</th><th>Corretor</th><th style={{ width: 44 }}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.code}>
                  <td><input type="checkbox" /></td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span style={{ width: 40, height: 40, borderRadius: 6, background: "var(--surface-header)", display: "grid", placeItems: "center", color: "var(--ink-faint)", flex: "none" }}><i className="bi bi-image"></i></span>
                      <div style={{ minWidth: 0 }}>
                        <a href="#" className="ax-strong" style={{ display: "block" }}>{r.title}</a>
                        <span style={{ fontSize: 11, color: "var(--ink-muted)", fontFamily: "var(--font-mono)" }}>{r.code} · {r.trans}</span>
                      </div>
                    </div>
                  </td>
                  <td>{r.tipo}</td>
                  <td>{r.bairro}</td>
                  <td>
                    <span style={{ display: "inline-flex", gap: 9, color: "var(--ink-muted)", fontSize: 12 }}>
                      <span><i className="bi bi-door-closed"></i> {r.dorm}</span>
                      <span><i className="bi bi-droplet"></i> {r.banho}</span>
                      <span><i className="bi bi-car-front"></i> {r.vaga}</span>
                      <span><i className="bi bi-arrows-fullscreen"></i> {r.area}</span>
                    </span>
                  </td>
                  <td className="ax-num" style={{ textAlign: "right" }}><strong style={{ color: "var(--ink)" }}>{r.preco}</strong></td>
                  <td><UM.Badge tone={r.status.c} dot={r.status.dot}>{r.status.t}</UM.Badge></td>
                  <td>{r.corretor}</td>
                  <td><button className="ax-ico-btn" aria-label="Ações"><i className="bi bi-three-dots-vertical"></i></button></td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px", fontSize: 12.5, color: "var(--ink-muted)" }}>
            <span>Mostrando 1–6 de 1.284</span>
            <div style={{ display: "inline-flex", gap: 6 }}>
              <UM.Button size="sm" icon="chevron-left" disabled>Anterior</UM.Button>
              <UM.Button size="sm" iconRight="chevron-right">Próximo</UM.Button>
            </div>
          </div>
        </div>
      </section>
    );
  }

  const SCREENS = { dashboard: Dashboard, leads: Leads, whatsapp: WhatsApp, imoveis: Imoveis };
  const Screen = SCREENS[current] || (() => (
    <section>
      <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr)" }}>
        <div><span className="ax-eyebrow">Módulo</span><h1 style={{ marginTop: 3 }}>{(CONTEXT[current] || {}).title || current}</h1><p>Selecione Painel, Imóveis, Leads ou WhatsApp para os fluxos completos.</p></div>
      </div>
      <div className="ax-panel"><UM.EmptyState icon="grid-3x3-gap" title="Módulo do CRM">Item de navegação da plataforma Unitymob.</UM.EmptyState></div>
    </section>
  ));
  const ctx = CONTEXT[current] || { crumb: [current] };
  const pins = [{ type: "property", label: "Apto 302 · COD-84213" }, { type: "lead", label: "Marina Costa" }];

  return (
    <div className="ax-app">
      <nav className="ax-navbar">
        <a className="ax-navbar__brand" href="#"><span className="ax-navbar__brand-mark"><svg viewBox="0 0 100 100" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="11" strokeLinecap="round" strokeLinejoin="round"><path d="M22 56 L50 33 L78 56"></path><path d="M31 73 L50 58 L69 73" opacity="0.5"></path></svg></span><span className="ax-navbar__brand-text">Unitymob <span>Plataforma</span></span></a>
        <div className="ax-navbar__spacer"></div>
        <div className="ax-navbar__search"><i className="bi bi-search" style={{ fontSize: 13 }}></i><input placeholder="Buscar imóveis, leads, código…" /></div>
        <a className="ax-navbar__primary"><i className="bi bi-plus-lg"></i> Novo</a>
        <button className="ax-navbar__user-trigger"><span className="ax-avatar" style={{ width: 22, height: 22, fontSize: 12 }}>MC</span><span>Marina Costa</span><i className="bi bi-chevron-down" style={{ fontSize: 11, color: "var(--ink-faint)" }}></i></button>
      </nav>
      <div className="ax-sidebar-contextbar"><span className="ax-contextbar__title"><i className="bi bi-layout-sidebar"></i><span>Explorer</span></span><button className="ax-ico-btn"><i className="bi bi-arrow-bar-left"></i></button></div>
      <div className="ax-contextbar">
        <nav className="ax-breadcrumb">
          <i className="bi bi-house-door"></i>
          {ctx.crumb.map((c, i) => (
            <React.Fragment key={i}><i className="bi bi-chevron-right"></i>{i === ctx.crumb.length - 1 ? <strong>{c}</strong> : <a href="#">{c}</a>}</React.Fragment>
          ))}
        </nav>
        <div className="ax-contextbar__pins">{pins.map((p, i) => <UM.ContextPin key={i} type={p.type}>{p.label}</UM.ContextPin>)}</div>
        <div className="ax-contextbar__actions"><UM.Button size="sm" icon="funnel">Filtros</UM.Button><UM.Button size="sm" variant="primary" icon="plus-lg">Novo</UM.Button></div>
      </div>
      <aside className="ax-sidebar">
        <ul className="ax-nav">
          {NAV.map((item, i) => item.section
            ? <li key={i} className="ax-nav__section">{item.section}</li>
            : <li key={item.id}><UM.NavLink as="button" icon={item.icon} active={current === item.id} onClick={() => setCurrent(item.id)} style={{ width: "100%" }}>{item.label}</UM.NavLink></li>
          )}
        </ul>
      </aside>
      <main className="ax-main"><Screen /></main>
    </div>
  );
}

module.exports = { AdminApp };
