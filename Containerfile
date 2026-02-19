FROM registry.redhat.io/rhel9/rhel-bootc:9.6

ARG USHIFT_VER=4.21

# ------------------------------------------------------------
# Enable required repositories
# ------------------------------------------------------------
RUN arch="$(uname -m)" && \
    dnf config-manager \
        --set-enabled rhocp-${USHIFT_VER}-for-rhel-9-${arch}-rpms \
        --set-enabled fast-datapath-for-rhel-9-${arch}-rpms

# ------------------------------------------------------------
# Install required packages
# ------------------------------------------------------------
RUN dnf install -y \
        firewalld \
        microshift && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# ------------------------------------------------------------
# Configure firewall (offline)
# ------------------------------------------------------------
RUN firewall-offline-cmd \
        --zone=public \
        --add-port=22/tcp \
        --add-port=80/tcp \
        --add-port=443/tcp && \
    firewall-offline-cmd \
        --zone=trusted \
        --add-source=10.42.0.0/16 && \
    firewall-offline-cmd \
        --zone=trusted \
        --add-source=169.254.169.1

# ------------------------------------------------------------
# OVN requirement: make root filesystem rshared
# ------------------------------------------------------------
RUN cat > /etc/systemd/system/microshift-make-rshared.service <<'EOF'
[Unit]
Description=Make root filesystem shared
Before=microshift.service
ConditionVirtualization=container

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --make-rshared /

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Enable and mask systemd units
# ------------------------------------------------------------
RUN systemctl enable microshift-make-rshared.service && \
    systemctl enable microshift

    # Make the KUBECONFIG from MicroShift directly available for the root user
RUN mkdir -p /var/roothome/.kube && \
    cp /var/lib/microshift/resources/kubeadmin/kubeconfig /var/roothome/.kube/config
