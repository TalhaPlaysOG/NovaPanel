<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Nova Panel Version
    |--------------------------------------------------------------------------
    */
    'version' => '1.0.0',

    /*
    |--------------------------------------------------------------------------
    | Brand Configuration
    |--------------------------------------------------------------------------
    |
    | Administrators can customize these values in .env to adapt the panel's
    | branding to their organization or hosting service.
    |
    */
    'name' => env('NOVA_NAME', env('APP_NAME', 'Nova Panel')),

    'logo' => env('NOVA_LOGO', '/assets/svgs/nova.svg'),

    'favicon' => env('NOVA_FAVICON', '/favicons/favicon.ico'),

    'accent_color' => env('NOVA_ACCENT_COLOR', '#6366f1'),

    'footer_text' => env('NOVA_FOOTER_TEXT', 'Nova Panel'),

    'support_url' => env('NOVA_SUPPORT_URL', 'https://github.com/NovaPanel'),

    'docs_url' => env('NOVA_DOCS_URL', 'https://github.com/NovaPanel'),
];
