# Nova Panel - Brand Images & Assets (`img/`)

Welcome to the **Nova Panel Image Center**. This folder holds the raster branding
assets used in documentation, social cards and error pages.

When the installer runs, everything in this folder is copied to the panel's
public directory (`public/assets/img/`).

---

## Asset Directory Map

| File Name | Purpose / Where It Appears | Format | Dimensions |
| :--- | :--- | :--- | :--- |
| **`nova.png`** | Main header logo (navigation bar, login form, installer banner) | PNG | 500 &times; 120 px |
| **`nova-mark.png`** | Icon / Brand Mark (mobile header, collapsed sidebar, avatars) | PNG | 100 &times; 100 px |
| **`banner.png`** | Promo & Documentation Banner (README, Discord, social cards) | PNG | 1200 &times; 400 px |
| **`favicon.ico`** | Browser tab favicon | ICO | 16/32/48 px multi-size |
| **`favicon-32x32.png`** | High-DPI browser favicon | PNG | 32 &times; 32 px |
| **`not_found.png`** | 404 page error illustration | PNG | 600 &times; 417 px |
| **`server_error.png`** | 500 server error illustration | PNG | 600 &times; 375 px |
| **`server_installing.png`** | Server installation in-progress artwork | PNG | 600 &times; 418 px |
| **`pterodactyl.png`** | Pterodactyl attribution artwork | PNG | 512 &times; 512 px |

All images above have transparent backgrounds unless the artwork itself paints
one (for example `banner.png` and `server_installing.png`).

---

## How to Customize

1. **Replace the PNGs**:
   - Edit or regenerate the files above in any image editor (**Figma**,
     **Photoshop**, **GIMP**, **Affinity Photo**, ...).
   - Keep the same file names and the dimensions listed in the table so layouts
     do not shift.
   - The primary brand colors are:
     - Gradient Start: `#38bdf8` (Sky Blue)
     - Gradient Mid: `#818cf8` (Indigo)
     - Gradient End: `#c084fc` (Purple)
     - Accent Color: `#6366f1` (Indigo 500)

2. **Vector masters for the live logo**:
   - The panel header/sidebar load `/assets/svgs/nova.svg` and
     `/assets/svgs/nova-mark.svg` (see `panel/config/nova.php`).
   - Their editable SVG masters live in `panel/public/assets/svgs/`. Edit those
     files if you want to change the logo rendered inside the panel itself.
   - The PNGs in this folder are the documentation/social/error-page copies.

3. **Add Custom Images**:
   - You can drop `.png`, `.jpg`, `.svg`, or `.webp` images into this folder.
   - During installation everything in `img/` is made accessible under
     `/assets/img/`.

4. **Change Branding via Configuration**:
   - You can also point to custom logo URLs in `panel/config/nova.php` or `.env`:
     ```env
     NOVA_NAME="My Custom Game Host"
     NOVA_LOGO="/assets/svgs/nova.svg"
     NOVA_ACCENT_COLOR="#6366f1"
     ```
