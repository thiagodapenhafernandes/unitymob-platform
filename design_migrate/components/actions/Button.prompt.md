**Button** — the primary action control; use for any clickable command (save, create, filter). Neutral outlined by default; `variant="primary"` for the main affirmative action, `ghost` for tertiary, `danger` for destructive.

```jsx
<Button variant="primary" icon="plus-lg">Novo imóvel</Button>
<Button icon="funnel">Filtros</Button>
<Button variant="ghost" size="sm" icon="three-dots" />
```

Variants: `default · primary · ghost · danger · success · warning · info`. Sizes: `md` (30px) · `sm` (28px). Icons are Bootstrap Icons names without the `bi-` prefix. Set `block` to stretch full-width; `as="a"` for link buttons.
