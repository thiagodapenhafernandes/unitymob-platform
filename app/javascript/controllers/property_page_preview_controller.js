import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="property-page-preview"
export default class extends Controller {
  static targets = ["results", "count"]
  static values = { url: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const formData = new FormData(this.element)
    const params = new URLSearchParams()

    // Log for debugging
    console.log("Refreshing preview...")

    for (let [key, value] of formData.entries()) {
      // Logic to extract parameters from Rails-style names like 'landing_page[filter_params][min_area]'
      // or 'landing_page[filter_params][characteristics][]'
      const nameMatch = key.match(/\[filter_params\]\[(.*?)\]/)
      if (nameMatch) {
        let fieldName = nameMatch[1]

        // Handle array fields
        if (fieldName.endsWith('[]')) {
          params.append(fieldName, value)
        } else if (['neighborhood', 'characteristics', 'category', 'city'].includes(fieldName)) {
          // Force array format if it's one of these fields
          params.append(fieldName + "[]", value)
        } else {
          params.append(fieldName, value)
        }
      }
    }

    const url = `${this.urlValue}?${params.toString()}`

    fetch(url, {
      headers: {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => response.json())
      .then(data => {
        this.renderDashboard(data)
      })
      .catch(error => {
        console.error("Error fetching preview:", error)
        this.resultsTarget.innerHTML = `
        <div class="alert alert-danger small p-2">
          Erro ao carregar prévia. Verifique os logs.
        </div>
      `
      })
  }

  renderDashboard(data) {
    const { count, metrics } = data

    if (count === 0) {
      this.resultsTarget.innerHTML = `
        <div class="text-center py-5 w-100">
          <i class="bi bi-search text-muted" style="font-size: 2rem;"></i>
          <div class="mt-2 text-muted italic">Nenhum imóvel encontrado com esses filtros.</div>
        </div>
      `
      // Update the hero count too if visible
      if (this.hasCountTarget) {
        this.countTarget.textContent = "0 imóveis"
      }
      return
    }

    // Sort categories by volume
    const sortedDistribution = Object.entries(metrics.distribution)
      .sort(([, a], [, b]) => b - a)

    const distributionHtml = sortedDistribution.map(([cat, qty]) => {
      const percentage = (qty / count) * 100
      return `
        <div class="distribution-item">
          <div class="distribution-header">
            <span class="distribution-label">${cat}</span>
            <span class="distribution-count">${qty}</span>
          </div>
          <div class="progress-thin">
            <div class="progress-bar" role="progressbar" style="width: ${percentage}%"></div>
          </div>
        </div>
      `
    }).join('')

    this.resultsTarget.innerHTML = `
      <!-- Hero Metric -->
      <div class="preview-stat-hero">
        <span class="hero-value">${count}</span>
        <span class="hero-label">Imóveis Encontrados</span>
      </div>

      <div class="preview-stats-grid">
        <!-- Preço Médio -->
        <div class="preview-stat-card">
          <div class="stat-label"><i class="bi bi-tag-fill"></i> Preço Médio</div>
          <div class="stat-value">${metrics.avg_price}</div>
          <div class="stat-sub">Média dos resultados</div>
        </div>
        
        <!-- Variação -->
        <div class="preview-stat-card">
          <div class="stat-label"><i class="bi bi-bar-chart-fill"></i> Variação de Preço</div>
          <div class="stat-value" style="font-size: 1rem; color: var(--admin-text-main);">
            Min: <span class="text-secondary">${metrics.min_price}</span>
          </div>
          <div class="stat-value" style="font-size: 1rem; color: var(--admin-text-main);">
            Max: <span class="text-secondary">${metrics.max_price}</span>
          </div>
        </div>

        <!-- Distribuição por Categoria -->
        <div class="preview-stat-card">
          <div class="stat-label"><i class="bi bi-pie-chart-fill"></i> Por Categoria</div>
          <div class="distribution-list">
            ${distributionHtml}
          </div>
        </div>
      </div>
    `

    // Hide the legacy count badge if it exists
    if (this.hasCountTarget) {
      this.countTarget.classList.add('d-none')
    }
  }
}
