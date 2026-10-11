// Only a view preference is persisted; no lead or conversation data.
export const workspaceTabKey = "workspaceActiveTab";

export function mountWorkspaceTabs(root, storage) {
  const tabs = [...root.querySelectorAll("[data-workspace-tab]")];
  let interacted = false;
  let preferred = "lead";
  let pendingSave = Promise.resolve();
  function select(value, persist = false) {
    const selected = tabs.find(tab => tab.dataset.workspaceTab === value && !tab.disabled) || tabs[0];
    for (const tab of tabs) {
      const active = tab === selected;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
      root.querySelector(`#${tab.getAttribute("aria-controls")}`).hidden = !active;
    }
    if (persist) {
      interacted = true;
      preferred = selected.dataset.workspaceTab;
      pendingSave = pendingSave.then(() => storage.set({ [workspaceTabKey]: selected.dataset.workspaceTab })).catch(() => {});
    }
  }
  for (const tab of tabs) {
    tab.addEventListener("click", () => select(tab.dataset.workspaceTab, true));
    tab.addEventListener("keydown", event => {
      const available = tabs.filter(item => !item.disabled);
      const index = available.indexOf(tab);
      const target = event.key === "ArrowRight" ? (index + 1) % available.length
        : event.key === "ArrowLeft" ? (index + available.length - 1) % available.length
        : event.key === "Home" ? 0 : event.key === "End" ? available.length - 1 : null;
      if (target === null) return;
      event.preventDefault();
      select(available[target].dataset.workspaceTab, true);
      available[target].focus();
    });
  }
  root.addEventListener("workspace:lead-state", event => {
    for (const tab of tabs) tab.disabled = tab.dataset.workspaceTab !== "lead" && !event.detail;
    select(event.detail ? preferred : "lead");
  });
  select("lead");
  return storage.get(workspaceTabKey).then(saved => {
    if (!interacted) {
      preferred = saved[workspaceTabKey] || "lead";
      select(preferred);
    }
  }).catch(() => {});
}
