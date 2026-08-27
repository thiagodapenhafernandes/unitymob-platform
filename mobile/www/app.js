// Tela única de login do app híbrido: e-mail + senha, um só toque em
// "Entrar" resolve o servidor da conta (gateway de discovery) e autentica
// direto no servidor certo — sem nenhuma etapa antes disso.
//
// A autenticação em si é um POST real de formulário (não fetch/XHR) para
// {tenant_url}/mobile/sign_in, então não esbarra em CORS; esse endpoint é
// isento de CSRF de propósito (ver Mobile::SessionsController) exatamente
// para aceitar esse primeiro POST vindo de outra origem. Dali em diante é
// cookie de sessão normal, igual ao PWA web — a resposta redireciona para
// /field (sucesso), para o desafio de 2FA, ou de volta para a tela real de
// login com a mensagem de erro (credenciais inválidas, dispositivo bloqueado
// etc.), sem precisar de nenhum tratamento especial aqui.
//
// DISCOVERY_URL é injetado em tempo de build por ambiente (ver README deste
// diretório): staging/produção apontam pro gateway real; local aponta pro
// gateway rodando em localhost para o spike técnico.
(function () {
  // A checagem de sessão persistente (unitymob_tenant_url) já rodou antes
  // desta página ser desenhada — ver <script> no <head> de index.html. Se
  // chegamos até aqui é porque não havia sessão salva (ou veio de um logout
  // explícito), então o que resta é só a lógica do formulário de login.
  const DISCOVERY_URL = window.UNITYMOB_DISCOVERY_URL || "https://webhooks.unitymob.com.br/discovery/resolve";
  const STORAGE_KEY = "unitymob_tenant_url";

  const form = document.getElementById("login-form");
  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");
  const errorEl = document.getElementById("error");
  const errorTextEl = document.getElementById("error-text");
  const submitButton = document.getElementById("submit-button");
  const submitLabel = document.getElementById("submit-label");
  const revealButton = document.getElementById("reveal");

  // Botão de mostrar/ocultar senha (existia na tela mas sem nenhum
  // comportamento ligado a ele).
  const EYE_ICON = revealButton.innerHTML;
  const EYE_SLASH_ICON = '<svg viewBox="0 0 16 16" fill="currentColor">' +
    '<path d="M10.79 12.912l-1.614-1.615a3.5 3.5 0 0 1-4.474-4.474l-2.06-2.06C.938 6.278 0 8 0 8s3 5.5 8 5.5a7 7 0 0 0 2.79-.588M5.21 3.088A7 7 0 0 1 8 2.5c5 0 8 5.5 8 5.5s-.939 1.721-2.641 3.238l-2.062-2.062a3.5 3.5 0 0 0-4.474-4.474z"/>' +
    '<path d="M5.525 7.646a2.5 2.5 0 0 0 2.829 2.829zm4.95.708-2.829-2.83a2.5 2.5 0 0 1 2.829 2.829zm3.171 6-12-12 .708-.708 12 12z"/>' +
    "</svg>";

  revealButton.addEventListener("click", () => {
    const revealed = passwordInput.type === "text";
    passwordInput.type = revealed ? "password" : "text";
    revealButton.setAttribute("aria-pressed", String(!revealed));
    revealButton.setAttribute("aria-label", revealed ? "Mostrar senha" : "Ocultar senha");
    revealButton.innerHTML = revealed ? EYE_ICON : EYE_SLASH_ICON;
  });

  function showError(message) {
    errorTextEl.textContent = message;
    errorEl.classList.add("is-visible");
  }

  function hideError() {
    errorEl.classList.remove("is-visible");
    errorTextEl.textContent = "";
  }

  function setLoading(isLoading) {
    submitButton.disabled = isLoading;
    submitButton.classList.toggle("is-loading", isLoading);
    submitLabel.textContent = isLoading ? "Entrando..." : "Entrar";
  }

  function submitBridgeLogin(tenantUrl, email, password) {
    const base = tenantUrl.replace(/\/$/, "");
    const bridgeForm = document.createElement("form");
    bridgeForm.method = "POST";
    bridgeForm.action = `${base}/mobile/sign_in`;
    bridgeForm.style.display = "none";

    const emailField = document.createElement("input");
    emailField.name = "admin_user[email]";
    emailField.value = email;
    bridgeForm.appendChild(emailField);

    const passwordField = document.createElement("input");
    passwordField.name = "admin_user[password]";
    passwordField.value = password;
    bridgeForm.appendChild(passwordField);

    document.body.appendChild(bridgeForm);
    bridgeForm.submit();
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    hideError();
    setLoading(true);

    try {
      const response = await fetch(DISCOVERY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: emailInput.value }),
      });

      if (!response.ok) {
        showError("Não encontramos uma conta para esse e-mail.");
        setLoading(false);
        return;
      }

      const data = await response.json();
      localStorage.setItem(STORAGE_KEY, data.tenant_url);
      submitBridgeLogin(data.tenant_url, emailInput.value, passwordInput.value);
      // Não reabilita o botão aqui: a página está navegando (sucesso ou
      // fallback para a tela real de login com o erro do Devise).
    } catch (error) {
      showError("Falha de conexão. Verifique sua internet e tente novamente.");
      setLoading(false);
    }
  });
})();

// Alternância rápida dev local / produção — só pra teste interno, sem UI
// visível. 5 toques no logo em até 3s trocam a URL de discovery salva no
// localStorage (ver <script> no <head> de index.html que lê essa chave) e
// recarregam a página. Sem precisar editar código nem reconstruir o app
// pra alternar de ambiente — só troca a chave e recarrega.
(function () {
  const ENV_KEY = "unitymob_env_override";
  const LOCAL_DISCOVERY_URL = "http://192.168.0.42:4001/discovery/resolve";
  const TAP_COUNT = 5;
  const TAP_WINDOW_MS = 3000;

  const logo = document.querySelector(".logo-icon");
  if (!logo) return;

  function showBadge(text) {
    let badge = document.getElementById("env-switch-badge");
    if (!badge) {
      badge = document.createElement("div");
      badge.id = "env-switch-badge";
      badge.style.cssText =
        "position:fixed;top:calc(env(safe-area-inset-top, 0px) + 14px);left:50%;" +
        "transform:translateX(-50%);z-index:9999;padding:8px 16px;border-radius:999px;" +
        "background:#111827;color:#fff;font-size:13px;font-weight:700;" +
        "box-shadow:0 8px 20px rgba(0,0,0,.3);transition:opacity .25s ease;pointer-events:none;";
      document.body.appendChild(badge);
    }
    badge.textContent = text;
    badge.style.opacity = "1";
    window.clearTimeout(badge._hideTimer);
    badge._hideTimer = window.setTimeout(() => { badge.style.opacity = "0"; }, 2200);
  }

  let taps = 0;
  let tapTimer = null;

  logo.addEventListener("click", () => {
    taps += 1;
    window.clearTimeout(tapTimer);
    tapTimer = window.setTimeout(() => { taps = 0; }, TAP_WINDOW_MS);

    if (taps < TAP_COUNT) return;
    taps = 0;

    const isLocal = localStorage.getItem(ENV_KEY) === "local";
    if (isLocal) {
      localStorage.removeItem(ENV_KEY);
      showBadge("Ambiente: Produção");
    } else {
      localStorage.setItem(ENV_KEY, "local");
      showBadge("Ambiente: Local");
    }
    window.setTimeout(() => window.location.reload(), 700);
  });

  if (localStorage.getItem(ENV_KEY) === "local") {
    showBadge(`Ambiente: Local (${LOCAL_DISCOVERY_URL})`);
  }
})();
