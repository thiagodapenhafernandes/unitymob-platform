// Portado de NotificaLead: app/javascript/lib/image_editor.js. Motor original, isolado para Sprockets.
(() => {
// ImageEditor — engine do editor de imagem usado em /support/tickets/:id
//
// Arquitetura baseada em OBJETOS (não flatten no canvas). Cada anotação é um
// objeto persistido numa lista; o canvas é redesenhado a partir da imagem
// base + todos os objetos a cada frame. Isso destrava:
//   - Texto movível/editável/removível
//   - Borracha "inteligente" (remove o objeto sob o cursor, preserva imagem)
//   - Undo/Redo via operações (não snapshots base64 pesados)
//   - Setas, retângulos, elipses, blur de região, crop
//   - Zoom/pan desacoplado do conteúdo
//
// API consumida pelo support_ticket_controller:
//
//   const editor = new ImageEditor({
//     canvas: canvasEl,
//     onChange: () => {},       // dispara em toda mutação (pra refresh de UI)
//     onToolChange: (tool) => {},
//     onHistoryChange: ({ canUndo, canRedo }) => {}
//   })
//   editor.loadImage(img)
//   editor.setTool('draw')     // draw | text | erase | arrow | rect | ellipse | blur | crop | pan | move
//   editor.setColor('#ff0000')
//   editor.setSize(4)
//   editor.setPendingText('texto')  // pré-visualização de texto enquanto digita
//   editor.setShapeFill(true|false)
//   editor.undo() / editor.redo() / editor.clear()
//   editor.zoomIn() / editor.zoomOut() / editor.resetZoom() / editor.fitToScreen()
//   await editor.exportBlob()   // Promise<Blob>
//   editor.destroy()

const DEFAULT_COLOR = "#00ff66"
const DEFAULT_SIZE = 4
const MAX_HISTORY = 80
const BLUR_RADIUS = 12
const ARROW_HEAD_LEN_RATIO = 2.5 // arrow head ~= 2.5x line width, min 10
const HIT_TOLERANCE = 8 // px extra pra facilitar clique de borracha em traços finos
const TEXT_DEFAULT_FONT = "'Inter', 'Helvetica Neue', Arial, sans-serif"

// ========= Objetos (factory + draw + hitTest) =========

function makeStroke({ points, color, size }) {
  return {
    type: "stroke",
    points: points.map((p) => ({ x: p.x, y: p.y })),
    color,
    size,
    draw(ctx) {
      if (this.points.length === 0) return
      ctx.save()
      ctx.strokeStyle = this.color
      ctx.lineWidth = this.size
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.beginPath()
      ctx.moveTo(this.points[0].x, this.points[0].y)
      // Quadratic smoothing entre pontos
      for (let i = 1; i < this.points.length - 1; i++) {
        const midX = (this.points[i].x + this.points[i + 1].x) / 2
        const midY = (this.points[i].y + this.points[i + 1].y) / 2
        ctx.quadraticCurveTo(this.points[i].x, this.points[i].y, midX, midY)
      }
      const last = this.points[this.points.length - 1]
      ctx.lineTo(last.x, last.y)
      ctx.stroke()
      ctx.restore()
    },
    hitTest(x, y) {
      const tol = Math.max(this.size / 2 + HIT_TOLERANCE, 8)
      for (let i = 0; i < this.points.length - 1; i++) {
        const p1 = this.points[i]
        const p2 = this.points[i + 1]
        if (pointToSegmentDist(x, y, p1.x, p1.y, p2.x, p2.y) <= tol) return true
      }
      return false
    },
    move(dx, dy) {
      this.points.forEach((p) => { p.x += dx; p.y += dy })
    }
  }
}

function makeText({ x, y, text, fontSize, color, font }) {
  return {
    type: "text",
    x, y, text,
    fontSize: fontSize || 24,
    color: color || DEFAULT_COLOR,
    font: font || TEXT_DEFAULT_FONT,
    _bounds: null,
    draw(ctx) {
      ctx.save()
      ctx.font = `bold ${this.fontSize}px ${this.font}`
      ctx.textBaseline = "top"
      const lines = this.text.split("\n")
      const width = Math.max(...lines.map(line => ctx.measureText(line).width))
      const height = this.fontSize * 1.2 * lines.length
      this._bounds = { x: this.x, y: this.y, w: width, h: height }

      // Contorno branco/preto pra não sumir em fundos claros/escuros
      ctx.lineWidth = Math.max(2, this.fontSize / 12)
      ctx.strokeStyle = this._contrastColor(this.color)
      ctx.lineJoin = "round"
      lines.forEach((line, index) => ctx.strokeText(line, this.x, this.y + index * this.fontSize * 1.2))

      ctx.fillStyle = this.color
      lines.forEach((line, index) => ctx.fillText(line, this.x, this.y + index * this.fontSize * 1.2))
      ctx.restore()
    },
    hitTest(x, y) {
      if (!this._bounds) return false
      const b = this._bounds
      return x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h
    },
    move(dx, dy) { this.x += dx; this.y += dy },
    _contrastColor(hex) {
      // Retorna preto ou branco pra melhor contraste com a cor do texto
      if (!hex) return "#000000"
      const h = hex.replace("#", "")
      if (h.length < 6) return "#000000"
      const r = parseInt(h.slice(0, 2), 16)
      const g = parseInt(h.slice(2, 4), 16)
      const b = parseInt(h.slice(4, 6), 16)
      const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      return luminance > 0.5 ? "#000000" : "#ffffff"
    }
  }
}

function makeArrow({ x1, y1, x2, y2, color, size }) {
  return {
    type: "arrow",
    x1, y1, x2, y2, color, size,
    draw(ctx) {
      ctx.save()
      ctx.strokeStyle = this.color
      ctx.fillStyle = this.color
      ctx.lineWidth = this.size
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      const headLen = Math.max(10, this.size * ARROW_HEAD_LEN_RATIO)
      const angle = Math.atan2(this.y2 - this.y1, this.x2 - this.x1)
      // Linha (termina um pouco antes da ponta pra ficar limpo)
      const endX = this.x2 - Math.cos(angle) * headLen * 0.5
      const endY = this.y2 - Math.sin(angle) * headLen * 0.5
      ctx.beginPath()
      ctx.moveTo(this.x1, this.y1)
      ctx.lineTo(endX, endY)
      ctx.stroke()
      // Cabeça da seta (triângulo preenchido)
      ctx.beginPath()
      ctx.moveTo(this.x2, this.y2)
      ctx.lineTo(
        this.x2 - headLen * Math.cos(angle - Math.PI / 7),
        this.y2 - headLen * Math.sin(angle - Math.PI / 7)
      )
      ctx.lineTo(
        this.x2 - headLen * Math.cos(angle + Math.PI / 7),
        this.y2 - headLen * Math.sin(angle + Math.PI / 7)
      )
      ctx.closePath()
      ctx.fill()
      ctx.restore()
    },
    hitTest(x, y) {
      const tol = this.size + HIT_TOLERANCE
      return pointToSegmentDist(x, y, this.x1, this.y1, this.x2, this.y2) <= tol
    },
    move(dx, dy) { this.x1 += dx; this.y1 += dy; this.x2 += dx; this.y2 += dy }
  }
}

function makeRect({ x, y, w, h, color, size, fill }) {
  return {
    type: "rect",
    x, y, w, h, color, size, fill: !!fill,
    draw(ctx) {
      ctx.save()
      ctx.lineWidth = this.size
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      if (this.fill) {
        ctx.fillStyle = this.color
        ctx.fillRect(this.x, this.y, this.w, this.h)
      } else {
        ctx.strokeStyle = this.color
        ctx.strokeRect(this.x, this.y, this.w, this.h)
      }
      ctx.restore()
    },
    hitTest(x, y) {
      const { nx, ny, nw, nh } = this._norm()
      if (this.fill) {
        return x >= nx && x <= nx + nw && y >= ny && y <= ny + nh
      }
      const tol = this.size + HIT_TOLERANCE
      const insideOuter = x >= nx - tol && x <= nx + nw + tol && y >= ny - tol && y <= ny + nh + tol
      const insideInner = x >= nx + tol && x <= nx + nw - tol && y >= ny + tol && y <= ny + nh - tol
      return insideOuter && !insideInner
    },
    move(dx, dy) { this.x += dx; this.y += dy },
    _norm() {
      return {
        nx: Math.min(this.x, this.x + this.w),
        ny: Math.min(this.y, this.y + this.h),
        nw: Math.abs(this.w),
        nh: Math.abs(this.h)
      }
    }
  }
}

function makeEllipse({ cx, cy, rx, ry, color, size, fill }) {
  return {
    type: "ellipse",
    cx, cy, rx, ry, color, size, fill: !!fill,
    draw(ctx) {
      ctx.save()
      ctx.lineWidth = this.size
      ctx.beginPath()
      ctx.ellipse(this.cx, this.cy, Math.abs(this.rx), Math.abs(this.ry), 0, 0, Math.PI * 2)
      if (this.fill) {
        ctx.fillStyle = this.color
        ctx.fill()
      } else {
        ctx.strokeStyle = this.color
        ctx.stroke()
      }
      ctx.restore()
    },
    hitTest(x, y) {
      const rx = Math.max(1, Math.abs(this.rx))
      const ry = Math.max(1, Math.abs(this.ry))
      const dx = (x - this.cx) / rx
      const dy = (y - this.cy) / ry
      const d = dx * dx + dy * dy
      if (this.fill) return d <= 1
      // Borda: anel em torno de d=1
      const tol = 0.15
      return d >= (1 - tol) && d <= (1 + tol)
    },
    move(dx, dy) { this.cx += dx; this.cy += dy }
  }
}

function makeBlur({ x, y, w, h, radius }) {
  return {
    type: "blur",
    x, y, w, h, radius: radius || BLUR_RADIUS,
    // Blur é aplicado sobre o conteúdo já desenhado (imagem base).
    // Recorta a região, blura e redesenha sobre.
    draw(ctx) {
      const { nx, ny, nw, nh } = this._norm()
      if (nw < 2 || nh < 2) return
      ctx.save()
      // Pega o pedaço já desenhado (imagem base está por baixo dos objetos)
      try {
        const imageData = ctx.getImageData(nx, ny, nw, nh)
        const off = document.createElement("canvas")
        off.width = nw
        off.height = nh
        const offCtx = off.getContext("2d")
        offCtx.putImageData(imageData, 0, 0)
        // Aplica blur via filter em canvas temporário
        ctx.filter = `blur(${this.radius}px)`
        ctx.drawImage(off, nx, ny)
        ctx.filter = "none"
      } catch (_e) {
        // fallback: retângulo cinza
        ctx.fillStyle = "rgba(128,128,128,0.9)"
        ctx.fillRect(nx, ny, nw, nh)
      }
      ctx.restore()
    },
    hitTest(x, y) {
      const { nx, ny, nw, nh } = this._norm()
      return x >= nx && x <= nx + nw && y >= ny && y <= ny + nh
    },
    move(dx, dy) { this.x += dx; this.y += dy },
    _norm() {
      return {
        nx: Math.min(this.x, this.x + this.w),
        ny: Math.min(this.y, this.y + this.h),
        nw: Math.abs(this.w),
        nh: Math.abs(this.h)
      }
    }
  }
}

// ========= Helpers geométricos =========

function pointToSegmentDist(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1
  const dy = y2 - y1
  if (dx === 0 && dy === 0) return Math.hypot(px - x1, py - y1)
  let t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
  t = Math.max(0, Math.min(1, t))
  const cx = x1 + t * dx
  const cy = y1 + t * dy
  return Math.hypot(px - cx, py - cy)
}

// ========= Classe principal =========

class ImageEditor {
  constructor({ canvas, onChange, onToolChange, onHistoryChange, onRequestText }) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    this.onChange = onChange || (() => {})
    this.onToolChange = onToolChange || (() => {})
    this.onHistoryChange = onHistoryChange || (() => {})
    this.onRequestText = onRequestText || (() => {})

    this.image = null
    this.objects = []
    this.history = [] // lista de snapshots da `objects` serializada
    this.historyIndex = -1

    this.tool = "draw"
    this.color = DEFAULT_COLOR
    this.size = DEFAULT_SIZE              // espessura do traço (draw/arrow/rect/ellipse)
    this.textFontSize = 28                 // tamanho da fonte (text) — independente do traço
    this.blurRadius = BLUR_RADIUS          // intensidade do blur — independente do traço
    this.shapeFill = false
    this.pendingText = ""

    // Zoom/pan (transform do canvas)
    this.zoom = 1
    this.panX = 0
    this.panY = 0

    // Estado de interação corrente
    this._dragging = false
    this._dragStart = null
    this._currentObject = null
    this._panStart = null
    this._selectedObject = null
    this._moveOffset = null
    this._editingText = null

    // Bind dos listeners
    this._onPointerDown = this._onPointerDown.bind(this)
    this._onPointerMove = this._onPointerMove.bind(this)
    this._onPointerUp = this._onPointerUp.bind(this)
    this._onWheel = this._onWheel.bind(this)
    this._onDoubleClick = this._onDoubleClick.bind(this)

    this._attachListeners()
  }

  _attachListeners() {
    this.canvas.style.touchAction = "none"
    this.canvas.addEventListener("pointerdown", this._onPointerDown)
    this.canvas.addEventListener("pointermove", this._onPointerMove)
    this.canvas.addEventListener("pointerup", this._onPointerUp)
    this.canvas.addEventListener("pointercancel", this._onPointerUp)
    this.canvas.addEventListener("pointerleave", this._onPointerUp)
    this.canvas.addEventListener("wheel", this._onWheel, { passive: false })
    this.canvas.addEventListener("dblclick", this._onDoubleClick)
  }

  destroy() {
    this.canvas.removeEventListener("pointerdown", this._onPointerDown)
    this.canvas.removeEventListener("pointermove", this._onPointerMove)
    this.canvas.removeEventListener("pointerup", this._onPointerUp)
    this.canvas.removeEventListener("pointercancel", this._onPointerUp)
    this.canvas.removeEventListener("pointerleave", this._onPointerUp)
    this.canvas.removeEventListener("wheel", this._onWheel)
    this.canvas.removeEventListener("dblclick", this._onDoubleClick)
  }

  // ========== API pública ==========

  loadImage(img) {
    this.image = img
    this.canvas.width = img.naturalWidth
    this.canvas.height = img.naturalHeight
    this.objects = []
    this.history = []
    this.historyIndex = -1
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this._pushHistory()
    this._redraw()
    this._notifyHistory()
  }

  setTool(tool) {
    this.tool = tool
    this._selectedObject = null
    this._finalizeEditingText()
    this.onToolChange(tool)
    this._updateCursor()
  }

  setColor(color) { this.color = color }
  setSize(size) { this.size = Number(size) || DEFAULT_SIZE }
  setTextFontSize(px) { this.textFontSize = Math.max(8, Number(px) || 28) }
  setBlurRadius(px) { this.blurRadius = Math.max(2, Math.min(40, Number(px) || BLUR_RADIUS)) }
  setPendingText(text) { this.pendingText = text || "" }
  setShapeFill(fill) { this.shapeFill = !!fill }

  undo() {
    if (this.historyIndex <= 0) return
    this.historyIndex--
    this._restoreHistory()
    this._notifyHistory()
  }

  redo() {
    if (this.historyIndex >= this.history.length - 1) return
    this.historyIndex++
    this._restoreHistory()
    this._notifyHistory()
  }

  clear() {
    this.objects = []
    this._pushHistory()
    this._redraw()
    this._notifyHistory()
  }

  // Crop — recorta canvas para a seleção atual (se última = rect ou usa bounds do último objeto blur/rect)
  crop(region) {
    if (!region || region.w === 0 || region.h === 0) return false
    const { nx, ny, nw, nh } = {
      nx: Math.min(region.x, region.x + region.w),
      ny: Math.min(region.y, region.y + region.h),
      nw: Math.abs(region.w),
      nh: Math.abs(region.h)
    }
    // Exporta pixels atuais (imagem + objetos) e recria uma imagem cropped como base
    const srcCanvas = document.createElement("canvas")
    srcCanvas.width = this.canvas.width
    srcCanvas.height = this.canvas.height
    const srcCtx = srcCanvas.getContext("2d")
    this._drawBaseAndObjects(srcCtx) // flatten atual

    const cropCanvas = document.createElement("canvas")
    cropCanvas.width = Math.round(nw)
    cropCanvas.height = Math.round(nh)
    const cropCtx = cropCanvas.getContext("2d")
    cropCtx.drawImage(srcCanvas, nx, ny, nw, nh, 0, 0, nw, nh)

    const newImg = new Image()
    newImg.onload = () => {
      this.image = newImg
      this.canvas.width = newImg.naturalWidth
      this.canvas.height = newImg.naturalHeight
      this.objects = []
      this._pushHistory()
      this._redraw()
      this._notifyHistory()
    }
    newImg.src = cropCanvas.toDataURL("image/png")
    return true
  }

  zoomIn() { this._setZoom(this.zoom * 1.2) }
  zoomOut() { this._setZoom(this.zoom / 1.2) }
  resetZoom() { this.zoom = 1; this.panX = 0; this.panY = 0; this._applyTransform() }

  // O canvas usa CSS `max-w-full max-h-full` + flex-center no wrapper,
  // então o fit natural já acontece. fitToScreen apenas reseta zoom/pan
  // pra voltar ao estado "imagem inteira centralizada".
  fitToScreen() {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this._applyTransform()
  }

  addTextAt({ canvasX, canvasY, text, color, fontSize }) {
    const trimmed = (text || "").toString()
    if (!trimmed.trim()) return null
    const obj = makeText({
      x: canvasX,
      y: canvasY,
      text: trimmed,
      fontSize: fontSize || this.textFontSize,
      color: color || this.color
    })
    this.objects.push(obj)
    this._pushHistory()
    this._redraw()
    this._notifyHistory()
    return obj
  }

  // Converte um ponto da tela (clientX/Y) para coordenadas do canvas.
  // Útil pro controller posicionar o overlay de input de texto.
  screenToCanvas(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect()
    const scaleX = this.canvas.width / rect.width
    const scaleY = this.canvas.height / rect.height
    return {
      x: (clientX - rect.left) * scaleX,
      y: (clientY - rect.top) * scaleY
    }
  }

  // Converte um ponto do canvas (x,y) pra posição absoluta na viewport,
  // pra posicionar overlays DOM sobre o canvas.
  canvasToScreen(canvasX, canvasY) {
    const rect = this.canvas.getBoundingClientRect()
    const scaleX = rect.width / this.canvas.width
    const scaleY = rect.height / this.canvas.height
    return {
      x: rect.left + canvasX * scaleX,
      y: rect.top + canvasY * scaleY,
      scaleX,
      scaleY
    }
  }

  async exportBlob(type = "image/png") {
    // Cria canvas final flatten (imagem base + objetos)
    const out = document.createElement("canvas")
    out.width = this.canvas.width
    out.height = this.canvas.height
    const outCtx = out.getContext("2d")
    this._drawBaseAndObjects(outCtx)
    return new Promise((resolve) => out.toBlob(resolve, type, 0.92))
  }

  // ========== Event handlers (pointer) ==========

  _onPointerDown(event) {
    event.preventDefault()
    const pt = this._canvasPoint(event)
    this.canvas.setPointerCapture(event.pointerId)

    // Pan via middle button, ou tecla Space, ou ferramenta 'pan'
    if (event.button === 1 || this.tool === "pan") {
      this._panStart = { x: event.clientX, y: event.clientY, panX: this.panX, panY: this.panY }
      return
    }

    switch (this.tool) {
      case "draw":
        this._currentObject = makeStroke({
          points: [pt],
          color: this.color,
          size: this.size
        })
        this._dragging = true
        break

      case "erase": {
        // Remove o primeiro objeto sob o ponto (de cima pra baixo)
        const idx = this._hitIndexAt(pt.x, pt.y)
        if (idx >= 0) {
          this.objects.splice(idx, 1)
          this._pushHistory()
          this._redraw()
          this._notifyHistory()
        }
        break
      }

      case "text": {
        // Delegação: controller recebe o ponto (em coordenadas de canvas e de tela)
        // e abre um input inline no local. Ao confirmar, chama editor.addTextAt(...).
        this.onRequestText({
          canvasX: pt.x,
          canvasY: pt.y,
          clientX: event.clientX,
          clientY: event.clientY,
          color: this.color,
          fontSize: this.textFontSize
        })
        break
      }

      case "arrow":
        this._currentObject = makeArrow({
          x1: pt.x, y1: pt.y, x2: pt.x, y2: pt.y,
          color: this.color, size: this.size
        })
        this._dragging = true
        this._dragStart = pt
        break

      case "rect":
        this._currentObject = makeRect({
          x: pt.x, y: pt.y, w: 0, h: 0,
          color: this.color, size: this.size, fill: this.shapeFill
        })
        this._dragging = true
        this._dragStart = pt
        break

      case "ellipse":
        this._currentObject = makeEllipse({
          cx: pt.x, cy: pt.y, rx: 0, ry: 0,
          color: this.color, size: this.size, fill: this.shapeFill
        })
        this._dragging = true
        this._dragStart = pt
        break

      case "blur":
        this._currentObject = makeBlur({
          x: pt.x, y: pt.y, w: 0, h: 0,
          radius: this.blurRadius
        })
        this._dragging = true
        this._dragStart = pt
        break

      case "crop": {
        this._currentObject = { type: "__crop_selection__", x: pt.x, y: pt.y, w: 0, h: 0 }
        this._dragging = true
        this._dragStart = pt
        break
      }

      case "move": {
        const idx = this._hitIndexAt(pt.x, pt.y)
        if (idx >= 0) {
          this._selectedObject = this.objects[idx]
          this._moveOffset = pt
          this._dragging = true
        }
        break
      }
    }
  }

  _onPointerMove(event) {
    // Pan
    if (this._panStart) {
      const dx = event.clientX - this._panStart.x
      const dy = event.clientY - this._panStart.y
      this.panX = this._panStart.panX + dx
      this.panY = this._panStart.panY + dy
      this._applyTransform()
      return
    }
    if (!this._dragging) return

    const pt = this._canvasPoint(event)
    if (!this._currentObject && this.tool !== "move") return

    switch (this.tool) {
      case "draw":
        this._currentObject.points.push(pt)
        this._redraw({ overlay: this._currentObject })
        break
      case "arrow":
        this._currentObject.x2 = pt.x
        this._currentObject.y2 = pt.y
        this._redraw({ overlay: this._currentObject })
        break
      case "rect":
        this._currentObject.w = pt.x - this._dragStart.x
        this._currentObject.h = pt.y - this._dragStart.y
        this._redraw({ overlay: this._currentObject })
        break
      case "ellipse": {
        this._currentObject.cx = (this._dragStart.x + pt.x) / 2
        this._currentObject.cy = (this._dragStart.y + pt.y) / 2
        this._currentObject.rx = Math.abs(pt.x - this._dragStart.x) / 2
        this._currentObject.ry = Math.abs(pt.y - this._dragStart.y) / 2
        this._redraw({ overlay: this._currentObject })
        break
      }
      case "blur":
        this._currentObject.w = pt.x - this._dragStart.x
        this._currentObject.h = pt.y - this._dragStart.y
        this._redraw({ overlay: this._currentObject })
        break
      case "crop":
        this._currentObject.w = pt.x - this._dragStart.x
        this._currentObject.h = pt.y - this._dragStart.y
        this._redraw({ cropOverlay: this._currentObject })
        break
      case "move":
        if (this._selectedObject) {
          const dx = pt.x - this._moveOffset.x
          const dy = pt.y - this._moveOffset.y
          this._selectedObject.move(dx, dy)
          this._moveOffset = pt
          this._redraw()
        }
        break
    }
  }

  _onPointerUp(event) {
    if (this._panStart) { this._panStart = null; return }
    if (!this._dragging) return
    this._dragging = false

    if (this.tool === "crop" && this._currentObject) {
      const region = { ...this._currentObject }
      this._currentObject = null
      if (Math.abs(region.w) > 5 && Math.abs(region.h) > 5) {
        this.crop(region)
      } else {
        this._redraw()
      }
      return
    }

    if (this._currentObject && this._currentObject.type !== "__crop_selection__") {
      // Validar tamanho mínimo pra shapes/blur
      if (["rect", "ellipse", "blur", "arrow"].includes(this._currentObject.type)) {
        const size = this._currentObject.type === "ellipse"
          ? Math.max(this._currentObject.rx, this._currentObject.ry)
          : Math.max(Math.abs(this._currentObject.w || 0), Math.abs(this._currentObject.h || 0),
                     Math.hypot((this._currentObject.x2 || 0) - (this._currentObject.x1 || 0),
                                (this._currentObject.y2 || 0) - (this._currentObject.y1 || 0)))
        if (size < 3) {
          this._currentObject = null
          this._redraw()
          return
        }
      }
      this.objects.push(this._currentObject)
      this._currentObject = null
      this._pushHistory()
      this._notifyHistory()
    }

    if (this.tool === "move" && this._selectedObject) {
      this._pushHistory()
      this._notifyHistory()
      this._moveOffset = null
    }

    this._redraw()
  }

  _onWheel(event) {
    if (!event.ctrlKey && !event.metaKey) return
    event.preventDefault()
    const delta = event.deltaY < 0 ? 1.1 : 0.9
    this._setZoom(this.zoom * delta)
  }

  _onDoubleClick(event) {
    const pt = this._canvasPoint(event)
    const idx = this._hitIndexAt(pt.x, pt.y)
    if (idx < 0) return
    const obj = this.objects[idx]
    if (obj.type === "text") {
      const newText = prompt("Editar texto:", obj.text)
      if (newText === null) return
      const trimmed = newText.trim()
      if (!trimmed) {
        this.objects.splice(idx, 1)
      } else {
        obj.text = trimmed
      }
      this._pushHistory()
      this._redraw()
      this._notifyHistory()
    }
  }

  // ========== Internals ==========

  _canvasPoint(event) {
    const rect = this.canvas.getBoundingClientRect()
    const scaleX = this.canvas.width / rect.width
    const scaleY = this.canvas.height / rect.height
    return {
      x: (event.clientX - rect.left) * scaleX,
      y: (event.clientY - rect.top) * scaleY
    }
  }

  _hitIndexAt(x, y) {
    // De cima pra baixo (último desenhado primeiro)
    for (let i = this.objects.length - 1; i >= 0; i--) {
      if (this.objects[i].hitTest(x, y)) return i
    }
    return -1
  }

  _drawBaseAndObjects(ctx) {
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
    if (this.image) ctx.drawImage(this.image, 0, 0, this.canvas.width, this.canvas.height)
    this.objects.forEach((obj) => obj.draw(ctx))
  }

  _redraw({ overlay = null, cropOverlay = null } = {}) {
    this._drawBaseAndObjects(this.ctx)
    if (overlay) overlay.draw(this.ctx)
    if (cropOverlay) this._drawCropOverlay(cropOverlay)
    // Seleção
    if (this._selectedObject && this.tool === "move") {
      this._drawSelectionBox(this._selectedObject)
    }
  }

  _drawCropOverlay(sel) {
    const ctx = this.ctx
    const { nx, ny, nw, nh } = {
      nx: Math.min(sel.x, sel.x + sel.w),
      ny: Math.min(sel.y, sel.y + sel.h),
      nw: Math.abs(sel.w),
      nh: Math.abs(sel.h)
    }
    ctx.save()
    // Escurece tudo que está fora da seleção
    ctx.fillStyle = "rgba(0, 0, 0, 0.5)"
    ctx.fillRect(0, 0, this.canvas.width, ny)
    ctx.fillRect(0, ny + nh, this.canvas.width, this.canvas.height - (ny + nh))
    ctx.fillRect(0, ny, nx, nh)
    ctx.fillRect(nx + nw, ny, this.canvas.width - (nx + nw), nh)
    // Borda da seleção
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = 2
    ctx.setLineDash([6, 4])
    ctx.strokeRect(nx, ny, nw, nh)
    ctx.restore()
  }

  _drawSelectionBox(obj) {
    const ctx = this.ctx
    let bounds
    if (obj._bounds) bounds = obj._bounds
    else if (obj.type === "rect") {
      const { nx, ny, nw, nh } = obj._norm()
      bounds = { x: nx, y: ny, w: nw, h: nh }
    } else if (obj.type === "ellipse") {
      bounds = { x: obj.cx - obj.rx, y: obj.cy - obj.ry, w: obj.rx * 2, h: obj.ry * 2 }
    } else if (obj.type === "arrow") {
      const minX = Math.min(obj.x1, obj.x2), maxX = Math.max(obj.x1, obj.x2)
      const minY = Math.min(obj.y1, obj.y2), maxY = Math.max(obj.y1, obj.y2)
      bounds = { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
    } else {
      return
    }
    const pad = 4
    ctx.save()
    ctx.strokeStyle = "#22d3ee"
    ctx.lineWidth = 1.5
    ctx.setLineDash([4, 3])
    ctx.strokeRect(bounds.x - pad, bounds.y - pad, bounds.w + pad * 2, bounds.h + pad * 2)
    ctx.restore()
  }

  _setZoom(next) {
    this.zoom = Math.max(0.1, Math.min(5, next))
    this._applyTransform()
  }

  _applyTransform() {
    // Zoom/pan com origem no centro — mantém a imagem centralizada no wrapper
    // flex ao escalar. No estado neutro (zoom=1, pan=0) limpa o transform
    // pra não interferir no layout natural.
    if (this.zoom === 1 && this.panX === 0 && this.panY === 0) {
      this.canvas.style.transform = ""
      this.canvas.style.transformOrigin = ""
      return
    }
    this.canvas.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`
    this.canvas.style.transformOrigin = "center center"
  }

  _updateCursor() {
    const cursors = {
      draw: "crosshair",
      text: "text",
      erase: "cell",
      arrow: "crosshair",
      rect: "crosshair",
      ellipse: "crosshair",
      blur: "crosshair",
      crop: "crosshair",
      pan: "grab",
      move: "move"
    }
    this.canvas.style.cursor = cursors[this.tool] || "default"
  }

  _pushHistory() {
    const snap = this._serializeObjects()
    this.history = this.history.slice(0, this.historyIndex + 1)
    this.history.push(snap)
    if (this.history.length > MAX_HISTORY) this.history.shift()
    this.historyIndex = this.history.length - 1
    this.onChange()
  }

  _restoreHistory() {
    const snap = this.history[this.historyIndex]
    if (!snap) return
    this.objects = this._deserializeObjects(snap)
    this._redraw()
    this.onChange()
  }

  _serializeObjects() {
    // Serializa apenas dados (sem methods). Usamos JSON.stringify ignorando funções.
    return this.objects.map((o) => {
      const copy = { ...o }
      delete copy.draw
      delete copy.hitTest
      delete copy.move
      delete copy._norm
      delete copy._contrastColor
      return copy
    })
  }

  _deserializeObjects(snap) {
    return snap.map((o) => {
      switch (o.type) {
        case "stroke": return makeStroke(o)
        case "text": return makeText(o)
        case "arrow": return makeArrow(o)
        case "rect": return makeRect(o)
        case "ellipse": return makeEllipse(o)
        case "blur": return makeBlur(o)
        default: return null
      }
    }).filter(Boolean)
  }

  _notifyHistory() {
    this.onHistoryChange({
      canUndo: this.historyIndex > 0,
      canRedo: this.historyIndex < this.history.length - 1
    })
  }

  _finalizeEditingText() {
    this._editingText = null
  }
}

window.SupportImageEditor = ImageEditor;
})();
