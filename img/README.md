# Nova Panel - Brand Images & Assets (`img/`)

Welcome to the **Nova Panel Image Center**. This folder is your central place to customize, replace, and edit all visual assets for your Nova Panel installation.

When the installer runs (or when you run `nova update`), any images placed in this directory are automatically synced to the web panel's public directory.

---

## Asset Directory Map

| File Name | Purpose / Where It Appears | Format | Recommended Dimensions |
| :--- | :--- | :--- | :--- |
| **`nova.svg`** | Main header logo (navigation bar, login form, installer banner) | SVG | 500 &times; 120 px |
| **`nova-mark.svg`** | Icon / Brand Mark (mobile header, collapsed sidebar, avatars) | SVG | 100 &times; 100 px |
| **`banner.svg`** | Promo & Documentation Banner (README, Discord, social cards) | SVG | 1200 &times; 400 px |
| **`favicon.ico`** | Browser tab favicon | ICO | 16/32/48 px multi-size |
| **`favicon-32x32.png`** | High-DPI browser favicon | PNG | 32 &times; 32 px |
| **`not_found.svg`** | 404 page error illustration | SVG | 600 &times; 400 px |
| **`server_error.svg`** | 500 server error illustration | SVG | 600 &times; 400 px |
| **`server_installing.svg`** | Server installation in-progress artwork | SVG | 600 &times; 400 px |

---

## How to Customize

1. **Edit Existing SVGs**:
   - You can edit `nova.svg` and `nova-mark.svg` directly in any vector editor like **Figma**, **Inkscape**, **Adobe Illustrator**, or even a text editor.
   - The primary brand colors are:
     - Gradient Start: `#38bdf8` (Sky Blue)
     - Gradient Mid: `#818cf8` (Indigo)
     - Gradient End: `#c084fc` (Purple)
     - Accent Color: `#6366f1` (Indigo 500)

2. **Add Custom Images**:
   - You can drop `.png`, `.jpg`, `.svg`, or `.webp` images into this folder.
   - During installation, everything in `img/` is made accessible under `/assets/svgs/` and `/assets/img/`.

3. **Change Branding via Configuration**:
   - You can also point to custom logo URLs in `panel/config/nova.php` or `.env`:
     ```env
     NOVA_NAME="My Custom Game Host"
     NOVA_LOGO="/assets/svgs/nova.svg"
     NOVA_ACCENT_COLOR="#6366f1"
     ```
