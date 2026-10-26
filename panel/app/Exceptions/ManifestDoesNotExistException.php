<?php

namespace Pterodactyl\Exceptions;

if (interface_exists(\Spatie\Ignition\Contracts\ProvidesSolution::class)) {
    class ManifestDoesNotExistException extends \Exception implements \Spatie\Ignition\Contracts\ProvidesSolution
    {
        public function getSolution(): \Spatie\Ignition\Contracts\Solution
        {
            return new Solutions\ManifestDoesNotExistSolution();
        }
    }
} else {
    class ManifestDoesNotExistException extends \Exception
    {
    }
}
