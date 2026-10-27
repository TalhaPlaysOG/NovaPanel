<?php
/**
 * Nova Panel - Auto Node provisioning helper.
 *
 * Creates (or updates) a node, seeds its game port allocations and prints the
 * resulting node details as JSON so the shell installer can continue with the
 * Wings configuration generation and service startup.
 *
 * Usage:
 *   php auto-node.php --panel=/var/www/nova-panel --ip=203.0.113.10 \
 *       --name=Nova-Node-1 --scheme=http --memory=4096 --disk=51200 \
 *       --ports=25565-25575 --proxy=0
 */

use Pterodactyl\Models\Node;
use Pterodactyl\Models\Location;
use Pterodactyl\Services\Allocations\AssignmentService;
use Pterodactyl\Services\Nodes\NodeCreationService;

$options = getopt('', [
    'panel:',
    'ip:',
    'name:',
    'scheme:',
    'memory:',
    'disk:',
    'ports:',
    'proxy:',
]);

$panelDir = rtrim($options['panel'] ?? '', '/\\');
if ($panelDir === '' || !is_file($panelDir . '/vendor/autoload.php')) {
    fwrite(STDERR, "Could not locate a Nova Panel installation (vendor/autoload.php missing).\n");
    exit(1);
}

$ip = trim($options['ip'] ?? '');
if ($ip === '') {
    fwrite(STDERR, "A node IP address or hostname is required (--ip).\n");
    exit(2);
}

require_once $panelDir . '/vendor/autoload.php';

/** @var \Illuminate\Foundation\Application $app */
$app = require_once $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$name = trim($options['name'] ?? '');
if ($name === '') {
    $digits = preg_replace('/\D/', '', $ip);
    $name = 'Nova-Node-' . ($digits !== '' ? substr($digits, -4) : '1');
}

$scheme = strtolower(trim($options['scheme'] ?? 'http')) === 'https' ? 'https' : 'http';

$memory = (int) ($options['memory'] ?? 0);
$disk = (int) ($options['disk'] ?? 0);
$ports = trim($options['ports'] ?? '25565-25575');

$data = [
    'name' => $name,
    'description' => 'Auto-provisioned by Nova Panel',
    'fqdn' => $ip,
    'scheme' => $scheme,
    'public' => true,
    'behind_proxy' => (bool) ((int) ($options['proxy'] ?? 0)),
    'maintenance_mode' => false,
    'memory' => max(512, $memory ?: 512),
    'memory_overallocate' => 0,
    'disk' => max(1024, $disk ?: 1024),
    'disk_overallocate' => 0,
    'upload_size' => 100,
    'daemonBase' => '/var/lib/pterodactyl/volumes',
    'daemonSFTP' => 2022,
    'daemonListen' => 8080,
];

try {
    /** @var Location|null $location */
    $location = Location::query()->orderBy('id')->first();
    if (!$location) {
        $location = Location::query()->create([
            'short' => 'local',
            'long' => 'Local Node Location',
        ]);
    }

    $data['location_id'] = $location->id;

    /** @var Node|null $node */
    $node = Node::query()->where('fqdn', $ip)->first();
    if ($node) {
        $node->forceFill($data)->save();
        $state = 'updated';
    } else {
        /** @var Node $node */
        $node = $app->make(NodeCreationService::class)->handle($data);
        $state = 'created';
    }

    // Seed the requested game ports (ranges such as 25565-25575 are supported).
    $portList = array_values(array_filter(array_map('trim', explode(',', $ports))));
    try {
        $app->make(AssignmentService::class)->handle($node, [
            'allocation_ip' => '0.0.0.0',
            'allocation_ports' => $portList,
            'allocation_alias' => $ip,
        ]);
    } catch (Throwable $exception) {
        // Allocations already exist or the range is invalid; keep going so the
        // node itself is still usable.
    }

    echo json_encode([
        'state' => $state,
        'node_id' => $node->id,
        'uuid' => $node->uuid,
        'name' => $node->name,
        'fqdn' => $node->fqdn,
        'scheme' => $node->scheme,
        'location_id' => $node->location_id,
        'memory' => $node->memory,
        'disk' => $node->disk,
    ], JSON_UNESCAPED_SLASHES), PHP_EOL;
} catch (Throwable $exception) {
    fwrite(STDERR, 'Auto node provisioning failed: ' . $exception->getMessage() . PHP_EOL);
    exit(3);
}
