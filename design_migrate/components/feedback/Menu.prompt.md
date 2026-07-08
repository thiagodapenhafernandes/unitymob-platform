**Menu** — the floating dropdown attached to icon buttons and user avatars. Pass an `items` array; mark destructive rows with `danger` and dividers with `separator`.

```jsx
<Menu items={[
  { icon: "eye", label: "Ver detalhes", onClick: open },
  { icon: "pencil", label: "Editar" },
  { separator: true },
  { icon: "trash", label: "Excluir", danger: true },
]} />
```
