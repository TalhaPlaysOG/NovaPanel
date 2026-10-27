<?php
/**
 * Nova Panel - User creation helper.
 *
 * Creates a new panel user, or updates an existing account when the email or
 * username is already registered. Prints the resulting account as JSON.
 *
 * Usage:
 *   php create-user.php --panel=/var/www/nova-panel --email=a@b.com \
 *       --username=admin --first=Nova --last=Admin --password=secret --admin=1
 */

use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Hash;
use Pterodactyl\Services\Users\UserCreationService;

$options = getopt('', [
    'panel:',
    'email:',
    'username:',
    'first:',
    'last:',
    'password:',
    'admin::',
]);

$panelDir = rtrim($options['panel'] ?? '', '/\\');
if ($panelDir === '' || !is_file($panelDir . '/vendor/autoload.php')) {
    fwrite(STDERR, "Could not locate a Nova Panel installation (vendor/autoload.php missing).\n");
    exit(1);
}

$email = trim($options['email'] ?? '');
$username = trim($options['username'] ?? '');
$first = trim($options['first'] ?? '');
$last = trim($options['last'] ?? '');
$password = (string) ($options['password'] ?? (getenv('NOVA_USER_PASSWORD') ?: ''));
$admin = (bool) ((int) ($options['admin'] ?? 0));

if ($email === '' || $username === '' || $first === '' || $last === '' || $password === '') {
    fwrite(STDERR, "Email, username, first name, last name and password are all required.\n");
    exit(2);
}

require_once $panelDir . '/vendor/autoload.php';

/** @var \Illuminate\Foundation\Application $app */
$app = require_once $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

try {
    /** @var User|null $user */
    $user = User::query()
        ->where('email', $email)
        ->orWhere('username', $username)
        ->first();

    if ($user) {
        $user->forceFill([
            'email' => $email,
            'username' => $username,
            'name_first' => $first,
            'name_last' => $last,
            'password' => Hash::make($password),
            'root_admin' => $admin,
        ])->save();

        $state = 'updated';
    } else {
        /** @var User $user */
        $user = $app->make(UserCreationService::class)->handle([
            'email' => $email,
            'username' => $username,
            'name_first' => $first,
            'name_last' => $last,
            'password' => $password,
            'root_admin' => $admin,
            'language' => 'en',
        ]);

        $state = 'created';
    }

    echo json_encode([
        'state' => $state,
        'id' => $user->id,
        'uuid' => $user->uuid,
        'email' => $user->email,
        'username' => $user->username,
        'name' => $user->name,
        'root_admin' => (bool) $user->root_admin,
    ], JSON_UNESCAPED_SLASHES), PHP_EOL;
} catch (Throwable $exception) {
    fwrite(STDERR, 'User creation failed: ' . $exception->getMessage() . PHP_EOL);
    exit(3);
}
