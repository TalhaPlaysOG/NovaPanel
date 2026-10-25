<?php

namespace Pterodactyl\Http\ViewComposers;

use Illuminate\View\View;
use Pterodactyl\Services\Helpers\AssetHashService;

class AssetComposer
{
    /**
     * AssetComposer constructor.
     */
    public function __construct(private AssetHashService $assetHashService)
    {
    }

    /**
     * Provide access to the asset service in the views.
     */
    public function compose(View $view): void
    {
        $view->with('asset', $this->assetHashService);
        $view->with('siteConfiguration', [
            'name' => config('nova.name') ?? config('app.name', 'Nova Panel'),
            'locale' => config('app.locale') ?? 'en',
            'recaptcha' => [
                'enabled' => config('recaptcha.enabled', false),
                'siteKey' => config('recaptcha.website_key') ?? '',
            ],
            'nova' => [
                'version' => config('nova.version', '1.0.0'),
                'logo' => config('nova.logo', '/assets/svgs/nova.svg'),
                'accent_color' => config('nova.accent_color', '#6366f1'),
                'footer_text' => config('nova.footer_text', 'Nova Panel'),
                'support_url' => config('nova.support_url', ''),
            ],
        ]);
    }
}
