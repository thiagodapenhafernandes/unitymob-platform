// Admin CRM shell — navbar + sidebar + context bar + screen router.
const UM = window.UnitymobDesignSystem_2a309d;
window.UM_SCREENS = window.UM_SCREENS || {};
if (window.UM_SCREENS.whatsapp) window.UM_SCREENS.wa_atendimento = window.UM_SCREENS.whatsapp;

const NAV = [
  { section: "Produto" },
  { id: "dashboard", icon: "speedometer2", label: "Painel" },
  { id: "imoveis", icon: "houses", label: "Imóveis" },
  { id: "leads", icon: "person-badge", label: "Leads" },
  { section: "Operação" },
  { id: "whatsapp", icon: "whatsapp", label: "WhatsApp", children: [
    { id: "wa_atendimento", icon: "chat-dots", label: "Atendimento" },
    { id: "wa_templates", icon: "grid-3x2-gap", label: "Templates" },
    { id: "wa_disparos", icon: "broadcast", label: "Disparos" },
  ] },
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
  dashboard:  { crumb: ["Painel"], title: "Painel", eyebrow: "Cockpit operacional" },
  imoveis:    { crumb: ["Imóveis"], title: "Imóveis" },
  imovel_form: { crumb: ["Imóveis", "Novo imóvel"], title: "Imóveis" },
  leads:      { crumb: ["Comercial", "Funil de Leads"], title: "Leads" },
  lead_detail: { crumb: ["Comercial", "Funil de Leads", "Detalhe"], title: "Leads" },
  whatsapp:   { crumb: ["WhatsApp", "Atendimento"], title: "WhatsApp" },
  wa_atendimento: { crumb: ["WhatsApp", "Atendimento"], title: "WhatsApp" },
  wa_templates: { crumb: ["WhatsApp", "Templates"], title: "Templates" },
  wa_disparos: { crumb: ["WhatsApp", "Disparos"], title: "Disparos" },
  automacao:  { crumb: ["Automação"], title: "Automação" },
  distribuicao:{ crumb: ["Distribuição de Leads"], title: "Distribuição" },
  captacoes:  { crumb: ["Captações"], title: "Captações" },
  proprietarios:{ crumb: ["Proprietários"], title: "Proprietários" },
  lojas:      { crumb: ["Lojas"], title: "Lojas" },
  usuarios:   { crumb: ["Usuários"], title: "Usuários" },
  marketing:  { crumb: ["Marketing"], title: "Marketing" },
};

function NavGroup({ item, current, onNavigate }) {
  const childActive = item.children.some((c) => c.id === current);
  const [open, setOpen] = React.useState(childActive);
  React.useEffect(() => { if (childActive) setOpen(true); }, [childActive]);
  return (
    <li>
      <UM.NavLink as="button" icon={item.icon} active={childActive} onClick={() => setOpen((o) => !o)} style={{ width: "100%" }}>
        {item.label}
        <i className="bi bi-chevron-down" style={{ marginLeft: 8, fontSize: 10, opacity: 0.6, transition: "transform .15s", transform: open ? "rotate(180deg)" : "none" }}></i>
      </UM.NavLink>
      {open && (
        <ul style={{ listStyle: "none", margin: "1px 0 3px", padding: 0 }}>
          {item.children.map((c) => (
            <li key={c.id}>
              <UM.NavLink as="button" icon={c.icon} active={current === c.id} onClick={() => onNavigate(c.id)} style={{ width: "100%", paddingLeft: 30 }}>{c.label}</UM.NavLink>
            </li>
          ))}
        </ul>
      )}
    </li>
  );
}

function Sidebar({ current, onNavigate }) {
  return (
    <aside className="ax-sidebar">
      <ul className="ax-nav">
        {NAV.map((item, i) =>
          item.section ? (
            <li key={i} className="ax-nav__section">{item.section}</li>
          ) : item.children ? (
            <NavGroup key={item.id} item={item} current={current} onNavigate={onNavigate} />
          ) : (
            <li key={item.id}>
              <UM.NavLink
                as="button"
                icon={item.icon}
                active={current === item.id}
                onClick={() => onNavigate(item.id)}
                style={{ width: "100%" }}
              >
                {item.label}
              </UM.NavLink>
            </li>
          )
        )}
      </ul>
    </aside>
  );
}

function Navbar() {
  return (
    <nav className="ax-navbar">
      <a className="ax-navbar__brand" href="#">
        <span className="ax-navbar__brand-mark"><svg viewBox="0 0 100 100" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="11" strokeLinecap="round" strokeLinejoin="round"><path d="M22 56 L50 33 L78 56"></path><path d="M31 73 L50 58 L69 73" opacity="0.5"></path></svg></span>
        <span className="ax-navbar__brand-text">Unitymob <span>Plataforma</span></span>
      </a>
      <div className="ax-navbar__spacer"></div>
      <div className="ax-navbar__search">
        <i className="bi bi-search" style={{ fontSize: 13 }}></i>
        <input placeholder="Buscar imóveis, leads, código…" />
      </div>
      <a className="ax-navbar__primary"><i className="bi bi-plus-lg"></i> Novo</a>
      <button className="ax-navbar__user-trigger">
        <span className="ax-avatar" style={{ width: 22, height: 22, fontSize: 12 }}>MC</span>
        <span>Marina Costa</span>
        <i className="bi bi-chevron-down" style={{ fontSize: 11, color: "var(--ink-faint)" }}></i>
      </button>
    </nav>
  );
}

function ContextBar({ current, pins }) {
  const ctx = CONTEXT[current] || { crumb: [current] };
  return (
    <>
      <div className="ax-sidebar-contextbar">
        <span className="ax-contextbar__title"><i className="bi bi-layout-sidebar"></i><span>Explorer</span></span>
        <button className="ax-ico-btn" aria-label="Recolher"><i className="bi bi-arrow-bar-left"></i></button>
      </div>
      <div className="ax-contextbar">
        <nav className="ax-breadcrumb">
          <i className="bi bi-house-door"></i>
          {ctx.crumb.map((c, i) => (
            <React.Fragment key={i}>
              <i className="bi bi-chevron-right"></i>
              {i === ctx.crumb.length - 1 ? <strong>{c}</strong> : <a href="#">{c}</a>}
            </React.Fragment>
          ))}
        </nav>
        {pins && pins.length > 0 && (
          <div className="ax-contextbar__pins">
            {pins.map((p, i) => (
              <UM.ContextPin key={i} type={p.type}>{p.label}</UM.ContextPin>
            ))}
          </div>
        )}
        <div className="ax-contextbar__actions">
          <UM.Button size="sm" icon="funnel">Filtros</UM.Button>
          <UM.Button size="sm" variant="primary" icon="plus-lg">Novo</UM.Button>
        </div>
      </div>
    </>
  );
}

function App() {
  const [current, setCurrent] = React.useState("dashboard");
  window.UM_GO = setCurrent;
  const pins = [
    { type: "property", label: "Apto 302 · COD-84213" },
    { type: "lead", label: "Marina Costa" },
  ];
  const Screen = window.UM_SCREENS[current] || (() => (
    <section>
      <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr)" }}>
        <div>
          <span className="ax-eyebrow">Módulo</span>
          <h1 style={{ marginTop: 3 }}>{(CONTEXT[current] && CONTEXT[current].title) || current}</h1>
          <p>Tela representada no kit — selecione Painel, Imóveis, Leads ou WhatsApp para os fluxos completos.</p>
        </div>
      </div>
      <div className="ax-panel">
        <UM.EmptyState icon="grid-3x3-gap" title="Módulo do CRM">
          Este item da navegação existe na plataforma Unitymob. Os quatro fluxos principais estão detalhados neste kit.
        </UM.EmptyState>
      </div>
    </section>
  ));
  return (
    <div className="ax-app">
      <Navbar />
      <ContextBar current={current} pins={pins} />
      <Sidebar current={current} onNavigate={setCurrent} />
      <main className="ax-main">
        <Screen />
      </main>
    </div>
  );
}

window.UM_App = App;
