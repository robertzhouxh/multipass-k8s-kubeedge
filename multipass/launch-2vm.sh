# multipass launch --name cks-master -c 4 -m 6G focal --disk 60G 
# multipass launch --name cks-worker -c 2 -m 2G focal --disk 60G 

## en0 表示要桥接的网卡
# multipass launch --name o-worker -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml--network en0

multipass launch --name master -c 4 -m 8G jammy --disk 60G --cloud-init systemd-resolved.yaml
multipass launch --name e-worker -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml
multipass launch --name e-node -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml




