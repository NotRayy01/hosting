#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Cloud VM Manager
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🎨 UI & STYLING (Ray's Signature Style)
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

pause() {
    echo -e "\n${CYAN}Press [ENTER] to continue...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Cloud VM Manager "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🌐 GLOBAL VARIABLES & CONFIG
# ==============================================================================
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

declare -A OS_OPTIONS=(
    ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Debian 12 Bookworm"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 11 Bullseye"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 13 Trixie (Daily)"]="debian|trixie|https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2|debian13|debian|debian"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# ==============================================================================
# 🛡️ DEPENDENCY CHECK
# ==============================================================================
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "lsof")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        info "Please run: sudo apt install qemu-system cloud-image-utils wget lsof"
        exit 1
    fi
}

# ==============================================================================
# 🧠 CORE HELPERS
# ==============================================================================
get_vm_list() { find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort; }

is_vm_running() {
    local vm_name="$1"
    pgrep -f "qemu-system.*$vm_name" >/dev/null && return 0
    load_vm_config "$vm_name" 2>/dev/null && [[ -n "${IMG_FILE:-}" ]] && pgrep -f "qemu-system.*${IMG_FILE}" >/dev/null && return 0
    return 1
}

load_vm_config() {
    local file="$VM_DIR/$1.conf"
    [[ -f "$file" ]] && source "$file" && return 0 || return 1
}

check_image_lock() {
    local img="$1" vm="$2"
    if lsof "$img" 2>/dev/null | grep -q qemu-system; then
        warn "Image is currently in use by another process."
        return 1
    fi
    local lock="${img}.lock"
    if [[ -f "$lock" ]] && ! find "$lock" -mmin +5 &>/dev/null; then
        return 1
    fi
    return 0
}

validate_input() {
    local type="$1" value="$2"
    case "$type" in
        number) [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
        size) [[ "$value" =~ ^[0-9]+[GMgm]$ ]] || return 1 ;;
        port) [[ "$value" =~ ^[0-9]+$ ]] && ((23 <= value && value <= 65535)) || return 1 ;;
        name) [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1 ;;
        username) [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1 ;;
    esac
    return 0
}

save_vm_config() {
    cat > "$VM_DIR/$VM_NAME.conf" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$(date)"
EOF
    ok "VM Configuration Saved."
}

# ==============================================================================
# 🖥️ VM SETUP & CONTROL
# ==============================================================================
setup_vm_image() {
    step "Setting up VM image..."
    mkdir -p "$VM_DIR"

    if [[ ! -f "$IMG_FILE" ]]; then
        info "Downloading $OS_TYPE base image (This may take a moment)..."
        wget --progress=bar:force:noscroll "$IMG_URL" -O "$IMG_FILE"
        ok "Download complete."
    fi

    qemu-img resize "$IMG_FILE" "$DISK_SIZE" &>/dev/null || true

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: $(openssl passwd -6 "$PASSWORD")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    echo "instance-id: iid-$VM_NAME" > meta-data
    echo "local-hostname: $HOSTNAME" >> meta-data

    cloud-localds "$SEED_FILE" user-data meta-data
    ok "Cloud-Init Seed generated. Ready for launch."
}

create_new_vm() {
    show_banner
    echo -e "${MAGENTA}--- ➕ Create New VM ---${NC}"

    local os_list=("${!OS_OPTIONS[@]}")
    local count=${#os_list[@]}
    for ((i=0; i<count; i++)); do
        echo -e " ${CYAN}$((i+1)))${NC} ${os_list[$i]}"
    done
    echo ""

    local choice
    while :; do
        read -p "🖥️  Select OS [1-$count]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && ((1 <= choice && choice <= count)) && break
        err "Invalid choice. Try again."
    done

    local sel="${os_list[$((choice-1))]}"
    IFS='|' read -r OS_TYPE CODENAME IMG_URL DEF_HOST DEF_USER DEF_PASS <<< "${OS_OPTIONS[$sel]}"

    echo ""
    read -p "📝 VM Name [$DEF_HOST]: " VM_NAME; VM_NAME=${VM_NAME:-$DEF_HOST}
    until validate_input name "$VM_NAME" && [[ ! -f "$VM_DIR/$VM_NAME.conf" ]]; do
        err "Invalid name or VM already exists."
        read -p "📝 VM Name: " VM_NAME
    done

    read -p "🌐 Hostname [$VM_NAME]: " HOSTNAME; HOSTNAME=${HOSTNAME:-$VM_NAME}
    read -p "👤 Username [$DEF_USER]: " USERNAME; USERNAME=${USERNAME:-$DEF_USER}
    
    echo -ne "🔑 Password [auto]: "
    read -s PASSWORD; echo
    PASSWORD=${PASSWORD:-$DEF_PASS}

    read -p "💾 Disk Size (e.g., 20G) [20G]: " DISK_SIZE; DISK_SIZE=${DISK_SIZE:-20G}
    until validate_input size "$DISK_SIZE"; do
        read -p "💾 Disk Size (e.g., 20G): " DISK_SIZE
    done

    read -p "🧠 RAM in MB [2048]: " MEMORY; MEMORY=${MEMORY:-2048}
    until validate_input number "$MEMORY"; do
        read -p "🧠 RAM in MB: " MEMORY
    done

    read -p "⚙️  CPU Cores [2]: " CPUS; CPUS=${CPUS:-2}
    until validate_input number "$CPUS"; do
        read -p "⚙️  CPU Cores: " CPUS
    done

    read -p "🔌 SSH Port [2222]: " SSH_PORT; SSH_PORT=${SSH_PORT:-2222}
    until validate_input port "$SSH_PORT" && ! ss -tln | grep -q ":$SSH_PORT "; do
        err "Port is invalid or already in use."
        read -p "🔌 SSH Port: " SSH_PORT
    done

    read -p "🖥️  Enable GUI mode? (y/n) [n]: " gui; GUI_MODE=false; [[ "$gui" =~ ^[Yy]$ ]] && GUI_MODE=true
    read -p "🔄 Extra Port Forwards (e.g. 8080:80, leave blank for none): " PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

    setup_vm_image
    save_vm_config
    
    ok "Virtual Machine '$VM_NAME' created successfully!"
    info "You can SSH into this VM using: ssh -p $SSH_PORT $USERNAME@localhost"
}

start_vm() {
    local vm="$1"
    load_vm_config "$vm"

    check_image_lock "$IMG_FILE" "$vm" || { err "Image is locked by another process."; return; }
    is_vm_running "$vm" && { warn "VM '$vm' is already running."; return; }

    local cmd=(
        qemu-system-x86_64 -enable-kvm -m "$MEMORY"M -smp "$CPUS" -cpu host
        -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=writeback
        -drive file="$SEED_FILE",format=raw,if=virtio
        -boot order=c
        -device virtio-net-pci,netdev=n0
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22
        -device virtio-balloon-pci
        -object rng-random,id=rng0,filename=/dev/urandom
        -device virtio-rng-pci,rng=rng0
    )

    if [[ -n "$PORT_FORWARDS" ]]; then
        IFS=',' read -ra fw <<< "$PORT_FORWARDS"
        local id=1
        for p in "${fw[@]}"; do
            IFS=':' read -r h g <<< "$p"
            cmd+=(-netdev user,id=n$id,hostfwd=tcp::"$h"-:"$g" -device virtio-net-pci,netdev=n$id)
            ((id++))
        done
    fi

    [[ "$GUI_MODE" == true ]] && cmd+=(-vga virtio -display gtk,gl=on) || cmd+=(-nographic)

    step "Launching VM: $vm"
    info "SSH Forwarded to port: $SSH_PORT"
    "${cmd[@]}"
    step "VM '$vm' has been shut down."
}

stop_vm() {
    local vm="$1"
    load_vm_config "$vm"
    is_vm_running "$vm" || { warn "VM '$vm' is not running."; return; }
    
    step "Stopping VM: $vm"
    pkill -f "qemu-system.*$IMG_FILE" || pkill -9 -f "qemu-system.*$IMG_FILE" || true
    rm -f "${IMG_FILE}.lock" 2>/dev/null
    ok "VM '$vm' stopped successfully."
}

delete_vm() {
    local vm="$1"
    load_vm_config "$vm"
    
    echo -e "${RED}⚠️  WARNING: You are about to permanently delete VM '$vm'.${NC}"
    read -p "Type YES to confirm: " c
    [[ "$c" == "YES" ]] || { info "Deletion cancelled."; return; }
    
    is_vm_running "$vm" && stop_vm "$vm"
    rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm.conf" "${IMG_FILE}.lock"
    ok "VM '$vm' completely deleted."
}

show_vm_info() {
    local vm="$1"
    load_vm_config "$vm"
    show_banner
    echo -e "${MAGENTA}--- 📋 Info: $vm ---${NC}"
    echo -e "${BOLD}OS:${NC} $OS_TYPE $CODENAME"
    echo -e "${BOLD}Hostname:${NC} $HOSTNAME"
    echo -e "${BOLD}Username:${NC} $USERNAME"
    echo -e "${BOLD}SSH Command:${NC} ssh -p $SSH_PORT $USERNAME@localhost"
    echo -e "${BOLD}Resources:${NC} $MEMORY MB RAM | $CPUS Core(s) | $DISK_SIZE Disk"
    echo -e "${BOLD}GUI Mode:${NC} $GUI_MODE"
    echo -e "${BOLD}Port Forwards:${NC} ${PORT_FORWARDS:-None}"
    
    if is_vm_running "$vm"; then
        echo -e "${BOLD}Status:${NC} ${GREEN}🟢 Running${NC}"
    else
        echo -e "${BOLD}Status:${NC} ${RED}🔴 Stopped${NC}"
    fi
}

edit_vm_config() {
    local vm="$1"
    load_vm_config "$vm"
    while :; do
        show_banner
        echo -e "${MAGENTA}--- 📝 Edit Config: $vm ---${NC}"
        echo "1) Hostname      [$HOSTNAME]"
        echo "2) Username      [$USERNAME]"
        echo "3) Password      [•••••••]"
        echo "4) SSH Port      [$SSH_PORT]"
        echo "5) GUI Mode      [$GUI_MODE]"
        echo "6) Port Forwards [$PORT_FORWARDS]"
        echo "7) RAM           [$MEMORY MB]"
        echo "8) CPUs          [$CPUS]"
        echo "9) Disk Size     [$DISK_SIZE]"
        echo "0) Back to Menu"
        echo ""
        read -p "Select setting to edit: " c
        case "$c" in
            1) read -p "New Hostname: " HOSTNAME ;;
            2) read -p "New Username: " USERNAME ;;
            3) echo -ne "New Password: "; read -s PASSWORD; echo ;;
            4) read -p "New SSH Port: " SSH_PORT ;;
            5) read -p "Enable GUI (y/n): " g; GUI_MODE=false; [[ "$g" =~ ^[Yy]$ ]] && GUI_MODE=true ;;
            6) read -p "New Port Forwards: " PORT_FORWARDS ;;
            7) read -p "New RAM (MB): " MEMORY ;;
            8) read -p "New CPUs: " CPUS ;;
            9) read -p "New Disk Size: " DISK_SIZE ;;
            0) return ;;
            *) warn "Invalid Option" ; continue ;;
        esac
        
        # If Hostname/User/Pass changed, rebuild cloud-init seed
        [[ "$c" =~ ^[1-3]$ ]] && setup_vm_image
        save_vm_config
        pause
    done
}

resize_vm_disk() {
    local vm="$1"
    load_vm_config "$vm"
    is_vm_running "$vm" && { err "You must stop the VM before resizing the disk."; return; }
    
    read -p "Enter new size (current is $DISK_SIZE): " size
    size=${size:-$DISK_SIZE}
    qemu-img resize "$IMG_FILE" "$size" && DISK_SIZE="$size" && save_vm_config
    ok "Disk successfully resized to $size."
}

show_vm_performance() {
    local vm="$1"
    load_vm_config "$vm"
    show_banner
    echo -e "${MAGENTA}--- 📈 Performance: $vm ---${NC}"
    if is_vm_running "$vm"; then
        local pid=$(pgrep -f "qemu-system.*$IMG_FILE")
        if [[ -n "$pid" ]]; then
            echo -e "${BOLD}PID   %CPU  %MEM  RSS    VSZ    COMMAND${NC}"
            ps -p "$pid" -o pid,%cpu,%mem,rss,vsz,cmd --no-headers
        fi
        echo -e "\n${BOLD}Host System Memory:${NC}"
        free -h
        echo -e "\n${BOLD}Host Disk Usage (VM Directory):${NC}"
        df -h "$(dirname "$IMG_FILE")"
    else
        warn "VM is not running."
        echo "Provisioned: $MEMORY MB RAM | $CPUS CPU | $DISK_SIZE Disk"
    fi
}

fix_vm_issues() {
    local vm="$1"
    load_vm_config "$vm"
    show_banner
    echo -e "${MAGENTA}--- 🛠️ Fix Issues: $vm ---${NC}"
    echo "1) 🔓 Clear file locks"
    echo "2) 💿 Rebuild Cloud-Init seed"
    echo "3) 📝 Rebuild configuration file"
    echo "4) 💀 Force kill stuck QEMU process"
    echo "0) Back"
    echo ""
    read -p "Choose an action: " c
    case "$c" in
        1) rm -f "${IMG_FILE}.lock"*; ok "Locks cleared." ;;
        2) rm -f "$SEED_FILE"; setup_vm_image ;;
        3) save_vm_config ;;
        4) pkill -9 -f "qemu-system.*$IMG_FILE" 2>/dev/null; ok "QEMU Process killed." ;;
        0) return ;;
        *) warn "Invalid Option" ;;
    esac
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
main_menu() {
    while :; do
        show_banner

        local vms=($(get_vm_list))
        local n=${#vms[@]}

        if (( n > 0 )); then
            echo -e "${GREEN}📦 Virtual Machines ($n):${NC}"
            for i in "${!vms[@]}"; do
                local status="🔴 Stopped"
                is_vm_running "${vms[$i]}" && status="${GREEN}🟢 Running${NC}"
                printf "  ${CYAN}%d)${NC} %-20s [%s]\n" "$((i+1))" "${vms[$i]}" "$status"
            done
            echo ""
        fi

        echo -e "${YELLOW}🎛️  Control Center${NC}"
        echo "1) ➕ Create New VM"
        
        if (( n > 0 )); then
            echo "2) ▶️  Start VM"
            echo "3) ⏹️  Stop VM"
            echo "4) ℹ️  Show Info"
            echo "5) 📝 Edit Config"
            echo "6) 🗑️  Delete VM"
            echo "7) 💾 Resize Disk"
            echo "8) 📈 Performance"
            echo "9) 🛠️  Fix Issues"
        fi
        echo "0) ❌ Exit"
        echo ""

        read -p "Select an option: " choice

        case "$choice" in
            1) create_new_vm ;;
            2|3|4|5|6|7|8|9)
                (( n == 0 )) && { warn "No VMs available. Create one first."; sleep 2; continue; }
                read -p "Select VM Number [1-$n]: " num
                if [[ "$num" =~ ^[0-9]+$ ]] && (( 1 <= num && num <= n )); then
                    vm="${vms[$((num-1))]}"
                    case "$choice" in
                        2) start_vm "$vm" ;;
                        3) stop_vm "$vm" ;;
                        4) show_vm_info "$vm" ;;
                        5) edit_vm_config "$vm" ;;
                        6) delete_vm "$vm" ;;
                        7) resize_vm_disk "$vm" ;;
                        8) show_vm_performance "$vm" ;;
                        9) fix_vm_issues "$vm" ;;
                    esac
                else
                    err "Invalid VM number."
                fi
                ;;
            0)
                show_banner
                echo -e "${CYAN}Thanks for using Ray Cloud VM Manager! Exiting...${NC}"
                exit 0
                ;;
            *) err "Invalid option."; sleep 1 ;;
        esac

        pause
    done
}

# ==============================================================================
# 🚀 BOOTSTRAP
# ==============================================================================
trap 'rm -f user-data meta-data 2>/dev/null' EXIT
check_dependencies
main_menu