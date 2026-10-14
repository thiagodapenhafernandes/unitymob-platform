import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "title", "state", "description", "clock", "summaryClock", "evidence", "inspector", "event", "zoomButton", "nextTitle", "action", "error"]
  static values = { data: Object, chartUrl: String }

  async connect() {
    this.connection = Symbol()
    const connection = this.connection
    this.selected = this.dataValue.initial
    this.selectKey(this.selected)
    this.resizeObserver = new ResizeObserver(() => this.chart?.resize())
    this.resizeObserver.observe(this.chartTarget)
    try {
      const echarts = await import(this.chartUrlValue)
      if (!this.element.isConnected || this.connection !== connection) return
      this.chart = echarts.init(this.chartTarget)
      this.chart.on("click", params => params.data?.key && this.selectKey(params.data.key))
      this.draw()
    } catch (_) {
      if (this.element.isConnected && this.connection === connection) this.errorTarget.hidden = false
    }
  }

  disconnect() {
    this.connection = null
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
    this.chart = null
  }

  select(event) { this.selectKey(event.currentTarget.dataset.key) }

  selectKey(key) {
    const data = this.dataValue
    const milestone = data.milestones.find(row => row.key === key)
    if (!milestone) return
    this.selected = key
    if (this.zoomed && data.milestones.indexOf(milestone) > 2) this.zoomed = false
    this.titleTarget.textContent = milestone.title
    this.stateTarget.textContent = milestone.state
    this.inspectorTarget.classList.toggle("is-pending", !milestone.confirmed)
    this.descriptionTarget.textContent = this.description(milestone)
    this.nextTitleTarget.textContent = {
      entry: "Conferir o cadastro e a origem", distribution: "Conferir a distribuição do lead",
      acceptance: "Acompanhar o responsável", contact: milestone.confirmed ? "Preparar o próximo passo comercial" : "Registrar o primeiro contato humano",
      visit: "Conferir a agenda e o resultado da visita", proposal: "Acompanhar a proposta comercial",
      closing: "Conferir a declaração do negócio fechado"
    }[key]
    this.actionTarget.textContent = key === "contact" && !milestone.confirmed ? "Registrar contato" : "Continuar em Atendimento"
    this.clockTarget.replaceChildren()
    this.clockTarget.hidden = !(key === "contact" && data.waiting)
    if (!this.clockTarget.hidden) {
      this.clockTarget.append(document.createTextNode(this.duration(data.entry_seconds)))
      const label = document.createElement("span")
      label.className = "ax-journey__clock-caption"
      label.textContent = `desde o cadastro${data.acceptance_seconds !== null ? ` · ${this.duration(data.acceptance_seconds)} desde o aceite` : ""}. Tempo no momento da consulta.`
      this.clockTarget.append(label)
    }
    this.summaryClockTarget.textContent = data.waiting ? `${this.duration(data.entry_seconds)} desde o cadastro${data.acceptance_seconds !== null ? ` · ${this.duration(data.acceptance_seconds)} desde o aceite` : ""}` : "Evidências das fontes existentes"
    this.evidenceTarget.replaceChildren()
    for (const evidence of milestone.evidence) {
      const details = document.createElement("details")
      const summary = document.createElement("summary")
      summary.textContent = evidence.source
      const time = document.createElement("time")
      time.dateTime = evidence.at
      time.textContent = evidence.date_label
      const actor = document.createElement("p")
      actor.textContent = evidence.actor ? `Registrado por: ${evidence.actor}` : "Autor não informado na fonte"
      const body = document.createElement("p")
      body.textContent = evidence.detail || "Evento registrado no histórico."
      details.append(summary, time, actor, body)
      this.evidenceTarget.append(details)
    }
    this.eventTargets.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.key === key)))
    this.zoomButtonTarget.lastChild.textContent = this.zoomed ? " Ver jornada inteira" : " Ampliar início"
    this.draw()
  }

  description(row) {
    if (row.key === "contact" && !row.confirmed) return "Resposta automática, aceite e tentativa sem resposta não confirmam contato humano. Consulte os registros operacionais abaixo."
    if (row.key === "visit") return "A agenda distingue agendamento de realização. A data exibida na fonte é o horário agendado da visita."
    if (row.key === "proposal") return "Cadastro, envio, visualização e decisão têm evidências próprias. Uma proposta aceita não comprova fechamento ou pagamento."
    if (row.key === "closing") return "O marco exige declaração explícita de negócio fechado no histórico; mudança de etapa sozinha não é suficiente."
    return row.evidence.length ? "Selecione a fonte abaixo para consultar data, autor e detalhes registrados." : "Este marco ainda não tem evidência registrada nas fontes consultadas."
  }

  duration(seconds) {
    if (seconds >= 86400) return `${Math.floor(seconds / 86400)} dias`
    if (seconds >= 3600) return `${Math.floor(seconds / 3600)} h ${Math.floor(seconds % 3600 / 60)} min`
    return `${Math.floor(seconds / 60)} min`
  }

  zoom() {
    this.zoomed = !this.zoomed
    this.zoomButtonTarget.lastChild.textContent = this.zoomed ? " Ver jornada inteira" : " Ampliar início"
    this.draw()
  }

  attendance() {
    this.element.closest("[data-controller~=ax-modal]")?.dispatchEvent(new CustomEvent("ax-modal:close"))
    if (this.selected === "contact") document.querySelector('#lead-attendance [title="Registrar contato"], #lead-attendance [aria-label="Registrar contato"]')?.click()
  }

  draw() {
    if (!this.chart) return
    const rows = this.dataValue.milestones
    const ink = getComputedStyle(this.element).color
    const muted = "#7d8ba0"
    const escape = value => String(value).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    this.chart.setOption({
      animation: !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      animationDuration: 180, aria: { enabled: true, label: { description: "Jornada nas perspectivas Entrada, Automação e Corretor. Selecione os eventos para consultar as evidências." } },
      grid: { left: 102, right: 36, top: 70, bottom: 88 },
      tooltip: { formatter: p => p.data?.key ? `${escape(p.data.name)}<br/>${escape(p.data.state)}` : "" },
      xAxis: { type: "category", data: rows.map(row => row.title), axisLabel: { color: muted, fontSize: 11, rotate: 28 }, axisLine: { lineStyle: { color: "#dfe7f1" } }, axisTick: { show: false } },
      yAxis: { type: "category", data: ["Corretor", "Automação", "Entrada"], axisLabel: { color: ink, fontSize: 12, fontWeight: 600 }, axisLine: { show: false }, axisTick: { show: false }, splitLine: { show: true, lineStyle: { color: "#e9eef5" } } },
      dataZoom: [{ type: "inside", start: 0, end: this.zoomed ? 35 : 100 }, { type: "slider", start: 0, end: this.zoomed ? 35 : 100, height: 16, bottom: 12, showDetail: false, borderColor: "transparent", fillerColor: "#365f8f22" }],
      series: [{ type: "line", silent: true, symbol: "none", data: rows.map(row => row.confirmed ? [row.title, row.lane] : null), lineStyle: { color: "#138c87", width: 2, type: "dashed" } },
        { type: "scatter", data: rows.map(row => {
          const selected = row.key === this.selected
          const color = row.confirmed ? row.lane === 1 ? "#8462c5" : "#138c87" : selected ? "#d99631" : "#b6c2d3"
          return { key: row.key, name: row.title, state: row.state, value: [row.title, row.lane], symbolSize: selected ? 25 : 16,
            itemStyle: { color, borderColor: "#fff", borderWidth: selected ? 5 : 2, shadowBlur: selected ? 16 : 0, shadowColor: `${color}55` },
            label: { show: selected || row.key === "entry" || row.key === "acceptance", position: "top", distance: 15, formatter: `${row.title}\n${row.confirmed && row.date_label ? row.date_label : row.confirmed ? row.state : "Sem confirmação"}`, fontSize: 10, lineHeight: 17, color: ink }
          }
        }), emphasis: { scale: 1.15 } }]
    }, { notMerge: true })
  }
}
