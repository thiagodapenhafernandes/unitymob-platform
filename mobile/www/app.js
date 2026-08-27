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
  const DISCOVERY_URL = window.UNITYMOB_DISCOVERY_URL || "https://webhooks.unitymob.com.br/discovery/resolve";
  const STORAGE_KEY = "unitymob_tenant_url";

  // Sessão persistente (remember_me de 6 meses, igual ao PWA web): se já
  // sabemos o servidor da última conta, pula esta tela e vai direto pro
  // /field — o cookie do WebView decide se ainda está logado. Só volta a
  // pedir e-mail/senha se o cookie expirou/foi revogado (a própria página
  // real de login aparece nesse caso) ou depois de um logout explícito
  // (que deve limpar esta chave — ver README deste diretório).
  const loggedOut = new URLSearchParams(window.location.search).get("logged_out") === "1";
  if (loggedOut) {
    localStorage.removeItem(STORAGE_KEY);
  } else {
    const savedTenantUrl = localStorage.getItem(STORAGE_KEY);
    if (savedTenantUrl) {
      window.location.href = savedTenantUrl.replace(/\/$/, "") + "/field";
      return;
    }
  }

  const form = document.getElementById("login-form");
  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");
  const errorEl = document.getElementById("error");
  const errorTextEl = document.getElementById("error-text");
  const submitButton = document.getElementById("submit-button");

  function showError(message) {
    errorTextEl.textContent = message;
    errorEl.classList.add("is-visible");
  }

  function hideError() {
    errorEl.classList.remove("is-visible");
    errorTextEl.textContent = "";
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
    submitButton.disabled = true;
    submitButton.textContent = "Entrando...";

    try {
      const response = await fetch(DISCOVERY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: emailInput.value }),
      });

      if (!response.ok) {
        showError("Não encontramos uma conta para esse e-mail.");
        submitButton.disabled = false;
        submitButton.textContent = "Entrar";
        return;
      }

      const data = await response.json();
      localStorage.setItem(STORAGE_KEY, data.tenant_url);
      submitBridgeLogin(data.tenant_url, emailInput.value, passwordInput.value);
      // Não reabilita o botão aqui: a página está navegando (sucesso ou
      // fallback para a tela real de login com o erro do Devise).
    } catch (error) {
      showError("Falha de conexão. Verifique sua internet e tente novamente.");
      submitButton.disabled = false;
      submitButton.textContent = "Entrar";
    }
  });
})();
