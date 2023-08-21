## en0 表示要桥接的网卡
# multipass launch --name o-worker -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml--network en0
# multipass launch --name k8s-node -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml
multipass launch --name master -c 4 -m 6G jammy --disk 30G --cloud-init systemd-resolved.yaml
multipass launch --name mec-n0 -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml
