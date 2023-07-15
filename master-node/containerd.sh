cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
 
# 安装ntpdate工具
apt-get install ntpdate -y
# 使用国家时间中心的源同步时间
ntpdate ntp.ntsc.ac.cn
# 最后查看一下时间
hwclock

# ------------------------------------------------------------------
# (Install containerd)
sudo apt-get update && sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

## Change CgroupDriver to systemd
## vim  /etc/containerd/config.toml    SystemdCgroup = true
sed -i 's#SystemdCgroup = false#SystemdCgroup = true#g' /etc/containerd/config.toml
sed -i "s#k8s.gcr.io#registry.cn-hangzhou.aliyuncs.com/google_containers#g"  /etc/containerd/config.toml
sed -i "s#https://registry-1.docker.io#https://registry.cn-hangzhou.aliyuncs.com#g"  /etc/containerd/config.toml

# Restart containerd
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd

# Install cri-dockerd: https://github.com/kubeedge/kubeedge/issues/4843
VERSION=0.3.4
wget https://github.com/Mirantis/cri-dockerd/releases/download/{VERSION}/cri-dockerd-{VERSION}.{ARCH}.tgz
tar zxf cri-dockerd-{VERSION}.{ARCH}.tgz 
cp cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd

wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/{VERSION}/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/{VERSION}/packaging/systemd/cri-docker.socket
cp cri-docker.service cri-docker.socket /etc/systemd/system/
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket
