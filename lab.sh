#!/bin/bash
set -euo pipefail

# -------------------------------------------------
# Colors
# -------------------------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

info()    { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; }

# -------------------------------------------------
# Load environment
# -------------------------------------------------
ENV_FILE="vars.env"

if [ -f "$ENV_FILE" ]; then
  info "Loading environment from $ENV_FILE"
  set -a
  source "$ENV_FILE"
  set +a
fi

ARCH="$(uname -m)"
ISO_NAME="rhel-9.6-${ARCH}-boot.iso"
ISO_PATH="/var/lib/libvirt/images/${ISO_NAME}"

# -------------------------------------------------
# Commands
# -------------------------------------------------

login_registries() {
  info "Logging into quay.io"
  sudo podman login quay.io --authfile auth.json

  info "Logging into registry.redhat.io"
  sudo podman login registry.redhat.io --authfile auth.json

  success "Registry login completed"
}

build_and_push_image() {
  info "Building image ${IMAGE_REF}"
  sudo podman build -t "${IMAGE_REF}" .

  info "Pushing image ${IMAGE_REF}"
  sudo podman push "${IMAGE_REF}" --authfile auth.json

  success "Image built and pushed"
}

generate_kickstart() {
  info "Generating config.toml"

  cat > config.toml <<EOF
[customizations.installer.kickstart]
contents = """
lang en_US.UTF-8
keyboard us
timezone UTC
text
reboot

user --name microshift --password redhat --plaintext --groups wheel
rootpw --lock

zerombr
clearpart --all --initlabel
reqpart --add-boot

part pv.01 --grow
volgroup rhel pv.01
logvol / --vgname=rhel --fstype=xfs --size=20480 --name=root

network --bootproto=dhcp --device=link --activate --onboot=on

%pre-install --log=/dev/console --erroronfail
mkdir -p /etc/ostree
cat > /etc/ostree/auth.json <<'EOF_AUTH'
$(cat "$AUTH_CONFIG")
EOF_AUTH
%end

%post --log=/dev/console --erroronfail
cat > /etc/crio/openshift-pull-secret <<'EOF_PULL'
$(cat "$PULL_SECRET")
EOF_PULL
chmod 600 /etc/crio/openshift-pull-secret
%end
"""
EOF

  success "Kickstart generated"
}

generate_iso() {
  info "Building ISO"

  sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "$(pwd)/output:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "$(pwd)/config.toml:/config.toml" \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    build \
    --type iso \
    "${IMAGE_REF}"

  info "Renaming ISO"
  mv ./output/bootiso/install.iso "./output/bootiso/${ISO_NAME}"

  info "Copying ISO to ${ISO_PATH}"
  sudo cp "./output/bootiso/${ISO_NAME}" "$ISO_PATH"

  success "ISO ready at ${ISO_PATH}"
}

create_vm() {
  info "Creating VM ${VMNAME}"

  sudo virt-install \
    --name "${VMNAME}" \
    --vcpus 8 \
    --memory 8192 \
    --disk path=/var/lib/libvirt/images/${VMNAME}.qcow2,size=30 \
    --network network="${NETNAME}",model=virtio \
    --events on_reboot=restart \
    --cdrom "${ISO_PATH}" \
    --wait

  success "VM ${VMNAME} created"
}

# -------------------------------------------------
# CLI
# -------------------------------------------------

case "${1:-}" in
  login)
    login_registries
    ;;
  image)
    build_and_push_image
    ;;
  kickstart)
    generate_kickstart
    ;;
  iso)
    generate_kickstart
    generate_iso
    ;;
  vm)
    create_vm
    ;;
  all)
    login_registries
    build_and_push_image
    generate_kickstart
    generate_iso
    create_vm
    ;;
  *)
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 login       - login to registries"
    echo "  $0 image       - build and push container image"
    echo "  $0 kickstart   - generate kickstart config"
    echo "  $0 iso         - build ISO"
    echo "  $0 vm          - create VM"
    echo "  $0 all         - run everything"
    exit 1
    ;;
esac
