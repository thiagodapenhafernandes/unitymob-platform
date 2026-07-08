**Tabs** — segmented control for switching sub-views inside a panel (e.g. list vs kanban, or property tabs).

```jsx
<Tabs value={view} onChange={setView} tabs={[
  { value: "funil", label: "Funil", icon: "kanban" },
  { value: "lista", label: "Lista", icon: "list-ul" },
]} />
```
