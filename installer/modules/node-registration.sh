#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Automated Node Registration Module (Dev & VPS)
# ==============================================================================

register_local_node() {
    print_step "Automating Local Node Registration & Wings Configuration..."

    # In Development / CodeSandbox Mode:
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        print_info "Development / CodeSandbox Mode: Skipping local Wings node configuration."
        print_info "Panel administration, user management, and API testing remain fully active."
        return 0
    fi

    # In Production VPS Mode:
    cd "${PANEL_DIR}" || print_fatal "Could not navigate to ${PANEL_DIR}"

    # 1. Calculate safe resource allocation limits
    local total_mem_mb
    total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local safe_mem_mb=$((total_mem_mb - 512))
    if [[ $safe_mem_mb -lt 512 ]]; then
        safe_mem_mb=512
    fi

    local free_disk_mb
    free_disk_mb=$(df -m /var/lib/pterodactyl/volumes 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -z "$free_disk_mb" ]]; then
        free_disk_mb=$(df -m / | awk 'NR==2 {print $4}')
    fi
    local safe_disk_mb=$((free_disk_mb - 2048))
    if [[ $safe_disk_mb -lt 1024 ]]; then
        safe_disk_mb=1024
    fi

    print_info "Configured Node Resources: Memory=${safe_mem_mb} MB, Disk=${safe_disk_mb} MB"

    # 2. Determine node FQDN and scheme. The panel may be exposed through a
    # Cloudflare tunnel, but Wings must be reachable directly by the panel.
    # Registering the tunnel hostname here would make every server action fail
    # because Cloudflare does not proxy Wings on port 8080.
    local node_fqdn="${PANEL_HOST:-127.0.0.1}"
    local node_scheme="http"
    if [[ "${ACCESS_MODE:-}" =~ ^tunnel ]]; then
        local node_public_ip
        node_public_ip=$(get_public_ip)
        if [[ -n "${node_public_ip}" ]]; then
            node_fqdn="${node_public_ip}"
        fi
        node_scheme="http"
    elif [[ "${USE_SSL:-0}" -eq 1 && "${ACCESS_MODE:-}" == "domain" ]]; then
        node_scheme="https"
    else
        node_scheme="http"
    fi

    # 3. Create Default Location if not present
    print_info "Ensuring default location exists..."
    php artisan p:location:make --short="local" --long="Local Node Location" >> "${INSTALL_LOG}" 2>&1 || true

    local loc_id
    loc_id=$(php -r '
        require "vendor/autoload.php";
        $app = require_once "bootstrap/app.php";
        $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
        $kernel->bootstrap();
        $loc = Pterodactyl\Models\Location::first();
        echo $loc ? $loc->id : 1;
    ' 2>/dev/null || echo "1")

    # 4. Create Node
    print_info "Registering node '${node_fqdn}' (Location #${loc_id})..."
    php artisan p:node:make \
        --name="Nova-Node-1" \
        --description="Primary Game Server Node" \
        --locationId="${loc_id}" \
        --fqdn="${node_fqdn}" \
        --scheme="${node_scheme}" \
        --public=1 \
        --proxy=0 \
        --maintenance=0 \
        --maxMemory="${safe_mem_mb}" \
        --overallocateMemory=0 \
        --maxDisk="${safe_disk_mb}" \
        --overallocateDisk=0 \
        --uploadSize=100 \
        --daemonListeningPort=8080 \
        --daemonSFTPPort=2022 \
        --daemonBase="/var/lib/pterodactyl/volumes" >> "${INSTALL_LOG}" 2>&1 || {
            print_warning "Node registration via CLI reported an existing entry or non-critical notice."
        }

    local node_id
    node_id=$(php -r '
        require "vendor/autoload.php";
        $app = require_once "bootstrap/app.php";
        $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
        $kernel->bootstrap();
        $node = Pterodactyl\Models\Node::first();
        echo $node ? $node->id : 1;
    ' 2>/dev/null || echo "1")

    print_info "Active Node ID: #${node_id}"

    # 5. Generate and install /etc/pterodactyl/config.yml
    print_info "Generating secure Wings configuration (/etc/pterodactyl/config.yml)..."
    mkdir -p /etc/pterodactyl
    if php artisan p:node:configuration "${node_id}" --format=yaml > /etc/pterodactyl/config.yml 2>> "${INSTALL_LOG}"; then
        chmod 600 /etc/pterodactyl/config.yml
        print_success "Wings configuration generated and permissions secured."
    else
        print_error "Failed to generate Wings configuration automatically."
        print_warning "You can generate it later via: php artisan p:node:configuration ${node_id} --format=yaml > /etc/pterodactyl/config.yml"
    fi

    # 6. Seed Default Minecraft Network Allocations (Ports 25565 - 25575)
    print_info "Provisioning default game port allocations (25565 - 25575)..."
    local node_alloc_ip="${node_fqdn}"
    if [[ "$node_alloc_ip" =~ ^https?:// ]]; then
        node_alloc_ip=$(echo "$node_alloc_ip" | sed -e 's|^https\?://||' -e 's|:[0-9]*$||')
    fi
    if [[ -z "$node_alloc_ip" ]]; then
        node_alloc_ip="0.0.0.0"
    fi

    php -r "
        require 'vendor/autoload.php';
        \$app = require_once 'bootstrap/app.php';
        \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
        \$kernel->bootstrap();
        \$node = Pterodactyl\Models\Node::find(${node_id});
        if (\$node) {
            \$service = app(Pterodactyl\Services\Allocations\AssignmentService::class);
            try {
                \$service->handle(\$node, [
                    'allocation_ip' => '0.0.0.0',
                    'allocation_ports' => ['25565-25575'],
                    'allocation_alias' => '${node_alloc_ip}',
                ]);
            } catch (\Exception \$e) {
                // Ignore if allocations already exist
            }
        }
    " >> "${INSTALL_LOG}" 2>&1 || true

    # 7. Start Wings Service and verify health
    print_info "Starting Wings service..."
    systemctl restart wings >> "${INSTALL_LOG}" 2>&1

    sleep 3
    if systemctl is-active --quiet wings; then
        print_success "Wings daemon is active and running."
    else
        print_warning "Wings daemon reported inactive. Inspect logs with: journalctl -u wings -n 50"
    fi

    print_success "Automated Node setup completed.\n"
}
