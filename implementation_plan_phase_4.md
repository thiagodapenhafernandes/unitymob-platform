# Fase 4: PWA (Progressive Web App) & Mobile Experience

## Overview
This phase aims to transform the Salute Imóveis admin interface into an "Installable App" (PWA) and refine the mobile experience. This allows brokers to easily access the system from their phones with an app-like feel.

## Goals
1.  **Installability**: Enable "Add to Home Screen" on iOS and Android.
2.  **App-Like Feel**: Remove browser UI (standalone mode), add splash screens and proper icons.
3.  **Mobile Optimization**: Ensure critical admin pages (Lead details, Property list) are perfectly usable on small screens.

## Implementation Steps

### 1. PWA Configuration
*   [ ] **Manifest.json**: Create/Configure `manifest.json` with:
    *   Name: "Salute Admin"
    *   Short Name: "Salute"
    *   Start URL: `/admin` (or root, but focused on admin usage)
    *   Display: `standalone`
    *   Theme Color: `#022B3A` (Primary Brand Color)
    *   Background Color: `#FFFFFF`
    *   Icons: Generate and link icons (192, 512, apple-touch-icon).

*   [ ] **Service Worker**:
    *   Implement a basic Service Worker to cache static assets (logo, CSS, JS) for faster load times.
    *   Configure offline fallback page (simple "You are offline" message).
    *   Use `pwa-rails` or standard Rails asset pipeline approach.

### 2. View Adjustments (Mobile First)
*   [ ] **Viewport Meta Tag**: Verify `viewport-fit=cover` for notched phones.
*   [ ] **Touch Icons**: Ensure Apple Touch Icons are correctly linked in `application.html.erb`.
*   [ ] **Responsive Tables**:
    *   Review `Admin::HabitationsController#index` and `#leads` table for mobile overflow.
    *   Implement "Card View" for mobile rows (hide table headers, show stacking cards) if necessary.
*   [ ] **Sticky Actions**: Ensure "Save" buttons in forms remain accessible (sticky bottom) on mobile (Already partially done in Habitation form, verify for others).

### 3. Verification
*   **Audit**: Use Chrome DevTools > Lighthouse to audit PWA status.
*   **Manual**: Test "Add to Home Screen" on Simulator or Device.
