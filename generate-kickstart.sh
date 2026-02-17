#!/bin/bash
set -euo pipefail

# Auto-load .env or vars.env if present
ENV_FILE="vars.env"

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment from $ENV_FILE"
  set -a
  source "$ENV_FILE"
  set +a
fi

cat >> config.toml <<EOF
[customizations.installer.kickstart]
contents = """
lang en_US.UTF-8
keyboard us
timezone UTC
text
reboot

zerombr
clearpart --all --initlabel
reqpart --add-boot

part pv.01 --grow
volgroup rhel pv.01
logvol / --vgname=rhel --fstype=xfs --size=10240 --name=root

rootpw --lock

network --bootproto=dhcp --device=link --activate --onboot=on

%pre-install --log=/dev/console --erroronfail

mkdir -p /etc/ostree
cat > /etc/ostree/auth.json <<'EOF_AUTH'
$(cat "$AUTH_CONFIG")
EOF_AUTH

%end

ostreecontainer --url "${IMAGE_REF}"

%post --log=/dev/console --erroronfail

cat > /etc/crio/openshift-pull-secret <<'EOF_PULL'
$(cat "$PULL_SECRET")
EOF_PULL

chmod 600 /etc/crio/openshift-pull-secret

%end
"""
EOF

echo "kickstart.ks generated successfully"
