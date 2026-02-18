# 🚀 Bootc Image → ISO → VM Workshop

Build an Image Mode RHEL image with Microshift 4.21 pre-installed, embed it into a bootable ISO, and deploy it as a virtual machine.

---

## Table of Contents

- [Step 0 – Environment Setup](#step-0--environment-setup)
- [Step 1 – Login to Registries](#step-1--login-to-registries)
- [Step 2 – Build & Push the Container Image](#step-2--build--push-the-container-image)
- [Step 3 – Generate Kickstart Config](#step-3--generate-kickstart-config)
- [Step 4 – Build the Bootable ISO](#step-4--build-the-bootable-iso)
- [Step 5 – Rename & Move the ISO](#step-5--rename--move-the-iso)
- [Step 6 – Create the Virtual Machine](#step-6--create-the-virtual-machine)
- [Quick Reference](#quick-reference)

---

## Step 0 – Environment Setup

Centralize all configuration in a single `vars.env` file. Edit the values to match your environment before running anything else.

**Create `vars.env`:**

```bash
cat > vars.env <<EOF
# Container image reference — replace <your-user> with your Quay.io username
export IMAGE_REF=quay.io/<your-user>/microshift-4.21-bootc:latest

# VM configuration
export VMNAME=bootc-vm
export NETNAME=default

# Registry authentication
export AUTH_CONFIG=$(pwd)/auth.json
export PULL_SECRET=$(pwd)/pull-secret.json
EOF
```

**Load the variables:**

```bash
source vars.env
```

> ℹ️ Run `source vars.env` at the start of every new shell session before running any other step.

---

## Step 1 – Login to Registries

Log into both registries using the same `auth.json` file.

```bash
source vars.env

sudo podman login quay.io --authfile auth.json
sudo podman login registry.redhat.io --authfile auth.json
```

This allows you to:
- **Push** images to `quay.io`
- **Pull** the RHEL bootc image builder from `registry.redhat.io`

---

## Step 2 – Build & Push the Container Image

Build your local bootc image and push it to your registry. This image will be embedded inside the ISO.

```bash
source vars.env

sudo podman build -t "${IMAGE_REF}" --authfile auth.json .
sudo podman push "${IMAGE_REF}" --authfile auth.json
```

---

## Step 3 – Generate Kickstart Config

Generate the `config.toml` file used by bootc image builder. This injects your image reference, registry auth, and OpenShift pull secret into the ISO installer.

```bash
source vars.env

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
logvol / --vgname=rhel --fstype=xfs --size=10240 --name=root

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
```

**What this config does:**

| Section | Purpose |
|---|---|
| `pre-install` | Injects registry auth so the installer can pull your image |
| `ostreecontainer` | Installs your bootc image as the OS |
| `post` | Injects the OpenShift pull secret for MicroShift |

---

## Step 4 – Build the Bootable ISO

Run the bootc image builder container to produce an ISO that embeds your image.

```bash
source vars.env

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
```

Output will be written to `./output/bootiso/install.iso`.

---

## Step 5 – Rename & Move the ISO

Give the ISO a descriptive name and copy it into the libvirt image store.

```bash
ARCH=$(uname -m)
ISO_NAME="rhel-9.6-${ARCH}-boot.iso"

mv ./output/bootiso/install.iso "./output/bootiso/${ISO_NAME}"
sudo cp "./output/bootiso/${ISO_NAME}" "/var/lib/libvirt/images/${ISO_NAME}"
```

---

## Step 6 – Create the Virtual Machine

Boot and install a VM from the ISO using `virt-install`. The Kickstart config handles the installation automatically.

```bash
source vars.env

ARCH=$(uname -m)
ISO_PATH="/var/lib/libvirt/images/rhel-9.6-${ARCH}-boot.iso"

sudo virt-install \
    --name "${VMNAME}" \
    --vcpus 2 \
    --memory 2048 \
    --disk path=/var/lib/libvirt/images/${VMNAME}.qcow2,size=20 \
    --network network="${NETNAME}",model=virtio \
    --events on_reboot=restart \
    --cdrom "${ISO_PATH}" \
    --wait
```

The VM will boot from the ISO, install automatically, reboot, and be ready for SSH.

---

## Quick Reference

Full sequence in order — paste after completing setup:

```bash
# 0. Load environment
source vars.env

# 1. Login
sudo podman login quay.io --authfile auth.json
sudo podman login registry.redhat.io --authfile auth.json

# 2. Build & push image
sudo podman build -t "${IMAGE_REF}" .
sudo podman push "${IMAGE_REF}"

# 3. Generate config.toml  →  (run Step 3 block above)

# 4. Build ISO
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$(pwd)/config.toml:/config.toml" \
  registry.redhat.io/rhel9/bootc-image-builder:latest \
  build --type iso "${IMAGE_REF}"

# 5. Move ISO
ARCH=$(uname -m)
ISO_NAME="rhel-9.6-${ARCH}-boot.iso"
mv ./output/iso/disk.iso "./output/iso/${ISO_NAME}"
sudo cp "./output/iso/${ISO_NAME}" "/var/lib/libvirt/images/${ISO_NAME}"

# 6. Create VM
ISO_PATH="/var/lib/libvirt/images/rhel-9.6-${ARCH}-boot.iso"
sudo virt-install \
    --name "${VMNAME}" --vcpus 2 --memory 2048 \
    --disk path=/var/lib/libvirt/images/${VMNAME}.qcow2,size=20 \
    --network network="${NETNAME}",model=virtio \
    --events on_reboot=restart \
    --location "${ISO_PATH}" --wait
```

---

✅ **Result:** A container-built OS image → bootable ISO → running VM.