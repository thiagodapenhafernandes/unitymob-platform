import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { cycle: Object, chartUrl: String, timeZone: String };

  async connect() {
    const connection = (this.connection = Symbol());
    try {
      await import(this.chartUrlValue);
      if (!this.element.isConnected || this.connection !== connection) return;
      this.chart = drawRace(this.element, this.cycleValue, this.timeZoneValue);
    } catch (error) {
      if (this.element.isConnected)
        this.element.querySelector("[data-race-error]").hidden = false;
      console.error("Falha ao carregar acompanhamento do bolsão", error);
    }
  }

  disconnect() {
    this.connection = null;
    this.chart?.destroy();
    this.chart = null;
  }
}

function drawRace(element, cycle, timeZone) {
  const start = Date.parse(cycle.start);
  const rows = cycle.rows.map((row) => {
    const points = row.points.map((p) => ({
      s: (Date.parse(p.at) - start) / 1000,
      k: p.state,
      channel: p.channel,
    }));
    const channelPoints = (name) =>
      points.filter(
        (p) => p.channel === name && ["Recebeu", "Leu"].includes(p.k),
      );
    const channelStatus = (name) => points.find((p) => p.channel === name)?.k;
    return {
      name: row.name,
      whatsapp: channelPoints("whatsapp"),
      push: channelPoints("push"),
      whatsappStatus: channelStatus("whatsapp"),
      pushStatus: channelStatus("push"),
      accepted: points.find((p) => p.k === "Atendeu")?.s,
    };
  });
  const fullWindow = Math.max(300, Math.ceil(cycle.duration / 60) * 60);
  element.querySelector("[data-race-chart]").style.height =
    Math.max(280, rows.length * 44 + 60) + "px";
  const colors = { Recebeu: "#3291c5", Leu: "#7c5acb", Atendeu: "#059669" };
  let channel = "whatsapp",
    windowSize = 300,
    period = "300";
  const clock = (s) => {
    return new Date(start + s * 1000).toLocaleTimeString("pt-BR", {
      timeZone,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  };
  function points(row, i) {
    return [
      ...row[channel].map((p) => ({
        ...p,
        x: p.k === "Recebeu" ? 0 : p.s,
        y: i,
        channel,
      })),
      ...(row.accepted === undefined
        ? []
        : [
            {
              x: row.accepted,
              s: row.accepted,
              y: i,
              k: "Atendeu",
              channel: "attendance",
            },
          ]),
    ].sort((a, b) => a.x - b.x);
  }
  const annotations = {
    id: "raceAnnotations",
    beforeDatasetsDraw(chart) {
      const {
        ctx,
        scales: { x, y },
        chartArea: a,
      } = chart;
      ctx.save();
      rows.forEach((row, i) => {
        if (row.accepted !== undefined) {
          ctx.fillStyle = "#f0faf5";
          ctx.fillRect(
            a.left - 8,
            y.getPixelForValue(i) - 17,
            a.right - a.left + 16,
            34,
          );
        }
        ctx.beginPath();
        ctx.strokeStyle = "#e7edf3";
        ctx.lineWidth = 2;
        ctx.moveTo(x.getPixelForValue(0), y.getPixelForValue(i));
        ctx.lineTo(a.right, y.getPixelForValue(i));
        ctx.stroke();
      });
      ctx.restore();
    },
    afterDatasetsDraw(chart) {
      const {
        ctx,
        scales: { x, y },
        chartArea: a,
      } = chart;
      ctx.save();
      ctx.font = "11px -apple-system, sans-serif";
      rows.forEach((row, i) => {
        const received = points(row, i).find(
          (p) => p.k === "Recebeu" && p.x <= windowSize,
        );
        if (received) {
          ctx.fillStyle = colors.Recebeu;
          ctx.fillText(
            clock(received.s).slice(0, 5),
            a.left,
            y.getPixelForValue(i) - 12,
          );
        }
        if (!points(row, i).length) {
          ctx.fillStyle = "#718096";
          ctx.fillText(
            row[channel + "Status"] || "Sem confirmação de entrega",
            a.left + 8,
            y.getPixelForValue(i) - 12,
          );
        }
        const groups = [];
        points(row, i)
          .filter((p) => p.x <= windowSize && p.k !== "Recebeu")
          .forEach((p) => {
            const px = x.getPixelForValue(p.x);
            const prev = groups.at(-1);
            if (prev && px - prev.px < 85) {
              prev.items.push(p);
              prev.px = px;
            } else groups.push({ px, items: [p] });
          });
        groups.forEach((group) => {
          const p = group.items.at(-1),
            text = group.items.map((p) => p.k).join(" · ");
          ctx.fillStyle = colors[p.k];
          const width = ctx.measureText(text).width;
          const px = Math.min(
            Math.max(group.px - width / 2, a.left),
            a.right - width,
          );
          ctx.fillText(
            text,
            px,
            y.getPixelForValue(i) + (group.px - a.left < 70 ? 15 : -12),
          );
          if (p.k === "Atendeu") {
            ctx.fillStyle = "#fff";
            ctx.font = "bold 12px sans-serif";
            ctx.textAlign = "center";
            ctx.fillText(
              "✓",
              x.getPixelForValue(p.x),
              y.getPixelForValue(i) + 4,
            );
            ctx.textAlign = "left";
            ctx.font = "11px -apple-system, sans-serif";
          }
        });
        const late = points(row, i).filter((p) => p.x > windowSize);
        if (late.length) {
          ctx.fillStyle = "#7c5acb";
          ctx.textAlign = "right";
          ctx.fillText(
            late.map((p) => p.k + " " + clock(p.x)).join(" · ") + " →",
            a.right,
            y.getPixelForValue(i) - 12,
          );
          ctx.textAlign = "left";
        }
      });
      ctx.restore();
    },
  };
  const chart = new window.Chart(element.querySelector("canvas"), {
    type: "scatter",
    data: { datasets: [] },
    plugins: [annotations],
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      layout: { padding: { top: 20, right: 16, bottom: 3 } },
      interaction: { mode: "nearest", intersect: true },
      plugins: {
        legend: { display: false },
        tooltip: {
          displayColors: true,
          filter: (item) => !item.dataset.guide,
          callbacks: {
            title: (items) => (items.length ? rows[items[0].raw.y].name : ""),
            label: (item) => {
              const p = item.raw;
              return (
                p.k +
                " · " +
                (p.channel === "attendance"
                  ? "Atendimento"
                  : p.channel === "push"
                    ? "App"
                    : "WhatsApp") +
                " · " +
                (p.k === "Recebeu" ? clock(p.s).slice(0, 5) : clock(p.s))
              );
            },
          },
        },
      },
      scales: {
        x: {
          type: "linear",
          min: 0,
          max: 300,
          border: { display: false },
          grid: { color: "#edf1f6", drawTicks: false },
          ticks: {
            stepSize: 60,
            padding: 8,
            color: "#718096",
            callback: (value) => clock(value).slice(0, 5),
          },
        },
        y: {
          type: "linear",
          reverse: true,
          min: -0.5,
          max: Math.max(rows.length - 0.5, 0.5),
          border: { display: false },
          grid: { display: false },
          afterBuildTicks: (axis) => {
            axis.ticks = rows.map((row, i) => ({ value: i }));
          },
          ticks: {
            padding: 20,
            color: "#344054",
            font: { size: 13, weight: 600 },
            callback: (value) => rows[value]?.name || "",
          },
        },
      },
    },
  });
  function render() {
    const datasets = [];
    element.querySelector("[data-race-delivered]").textContent = rows.filter(
      (row) => row[channel].some((p) => p.k === "Recebeu"),
    ).length;
    rows.forEach((row, i) => {
      const ps = points(row, i),
        visible = ps.filter((p) => p.x <= windowSize),
        last = ps.at(-1);
      if (ps.length)
        datasets.push({
          guide: true,
          data: [
            { x: Math.min(ps[0].x, windowSize), y: i },
            { x: Math.min(last.x, windowSize), y: i },
          ],
          showLine: true,
          borderColor: row.accepted === undefined ? "#b8c6d7" : "#70c6a3",
          borderWidth: 3,
          pointRadius: 0,
          pointHitRadius: 0,
          pointHoverRadius: 0,
        });
      ["Recebeu", "Leu", "Atendeu"].forEach((k) => {
        datasets.push({
          clip: false,
          data: visible.filter((p) => p.k === k),
          backgroundColor: k === "Leu" ? "#fff" : colors[k],
          borderColor: colors[k],
          pointRadius: k === "Atendeu" ? 10 : k === "Leu" ? 7 : 5,
          pointHoverRadius: 10,
          pointHitRadius: 10,
          pointBorderWidth: k === "Leu" ? 3 : 2,
          pointStyle: "circle",
        });
      });
    });
    chart.data.datasets = datasets;
    chart.options.scales.x.max = windowSize;
    chart.options.scales.x.ticks.stepSize =
      windowSize === 300
        ? 60
        : Math.max(60, Math.ceil(windowSize / 6 / 60) * 60);
    chart.update();
    element
      .querySelectorAll("[data-channel]")
      .forEach((b) =>
        b.setAttribute("aria-pressed", b.dataset.channel === channel),
      );
    element
      .querySelectorAll("[data-window]")
      .forEach((b) =>
        b.setAttribute("aria-pressed", b.dataset.window === period),
      );
    element.querySelector("[data-race-read]").textContent =
      channel === "whatsapp"
        ? rows.filter((row) => row.whatsapp.some((p) => p.k === "Leu")).length
        : "—";
    element.querySelector("[data-race-readlabel]").textContent =
      channel === "whatsapp" ? "Leram no WhatsApp" : "Leitura não registrada";
    const outside = rows
      .flatMap((row, i) => points(row, i))
      .filter((p) => p.x > windowSize).length;
    element.querySelector("[data-race-windownote]").textContent = outside
      ? outside + " evento fora deste intervalo · veja o período completo"
      : "Todos os eventos do canal no período";
  }
  element.querySelectorAll("[data-channel]").forEach(
    (b) =>
      (b.onclick = () => {
        channel = b.dataset.channel;
        render();
      }),
  );
  element.querySelectorAll("[data-window]").forEach(
    (b) =>
      (b.onclick = () => {
        period = b.dataset.window;
        windowSize = period === "all" ? fullWindow : 300;
        render();
      }),
  );
  render();

  return chart;
}
