echo "===> 初始化系统"
echo ""

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

echo "===> 安装 Containerd"
echo ""
# ------------------------------------------------------------------
# (Install containerd)- 或者 https://github.com/containerd/containerd/blob/main/docs/getting-started.md#step-3-installing-cni-plugins
sudo apt-get update && sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

## Change CgroupDriver to systemd
# sudo sed -i 's#systemd_cgroup = false#systemd_cgroup = true#g' /etc/containerd/config.toml
sudo sed -i 's#SystemdCgroup = false#SystemdCgroup = true#g' /etc/containerd/config.toml
sudo sed -i "s#k8s.gcr.io#registry.cn-hangzhou.aliyuncs.com/google_containers#g"  /etc/containerd/config.toml
sudo sed -i "s#registry.k8s.io#registry.cn-hangzhou.aliyuncs.com/google_containers#g"  /etc/containerd/config.toml
sudo sed -i "s#https://registry-1.docker.io#https://registry.cn-hangzhou.aliyuncs.com#g"  /etc/containerd/config.toml

# Restart containerd
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd

echo "===> 安装 CNI"
echo ""
# Install CNI
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-arm64-v1.3.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-arm64-v1.3.0.tgz
cat > /etc/cni/net.d/10-containerd-net.conflist <<EOF
{
     "cniVersion": "1.0.0",
     "name": "containerd-net",
     "plugins": [
       {
         "type": "bridge",
         "bridge": "cni0",
         "isGateway": true,
         "ipMasq": true,
         "promiscMode": true,
         "ipam": {
           "type": "host-local",
           "ranges": [
             [{
               "subnet": "10.88.0.0/16"
             }],
             [{
               "subnet": "2001:db8:4860::/64"
             }]
           ],
           "routes": [
             { "dst": "0.0.0.0/0" },
             { "dst": "::/0" }
           ]
         }
       },
       {
         "type": "portmap",
         "capabilities": {"portMappings": true}
       }
     ]
    }
EOF

echo "===> 安装 nerdcrl"
echo ""
wget https://github.com/containerd/nerdctl/releases/download/v1.5.0/nerdctl-1.5.0-linux-arm64.tar.gz
tar Cxzvvf /usr/local/bin nerdctl-1.5.0-linux-arm64.tar.gz

echo "===> 重启 containerd"
echo ""
# Restart containerd
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd
