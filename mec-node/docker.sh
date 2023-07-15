# (Install Docker CE)

## Set up the repository:
### Install packages to allow apt to use a repository over HTTPS
sudo apt-get update && sudo apt-get install -y \
  apt-transport-https ca-certificates curl software-properties-common gnupg2

# 安装ntpdate工具
apt-get install ntpdate -y
# 使用国家时间中心的源同步时间
ntpdate ntp.ntsc.ac.cn
# 最后查看一下时间
hwclock

# Add Docker's official GPG key:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -

# Add the Docker apt repository:
sudo add-apt-repository \
  "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"

# Install Docker CE
## sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
## 安装特定版本, 查版本号: apt-cache madison docker-ce
## 建议20.10
sudo apt-get update && sudo apt-get install -y \
  containerd.io=1.6.9-1 \
  docker-ce=5:20.10.24~3-0~ubuntu-$(lsb_release -cs) \
  docker-ce-cli=5:20.10.24~3-0~ubuntu-$(lsb_release -cs)

#sudo apt-get update && sudo apt-get install -y \
#  containerd.io=1.6.9-1 \
#  docker-ce=5:23.0.6-1~ubuntu.22.04~$(lsb_release -cs) \
#  docker-ce-cli=5:23.0.6-1~ubuntu.22.04~$(lsb_release -cs) 
#  # docker-buildx-plugin=0.10.5-1~ubuntu.22.04~$(lsb_release -cs) \
#  # docker-compose-plugin=2.6.0~ubuntu.22.04~$(lsb_release -cs) 

# Set up the Docker daemon
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "registry-mirrors":["https://bycacelf.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Create /etc/systemd/system/docker.service.d
sudo mkdir -p /etc/systemd/system/docker.service.d

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

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

# https://github.com/containerd/containerd/blob/main/docs/getting-started.md#step-3-installing-cni-plugins
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-arm64-v1.3.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-arm64-v1.3.0.tgz
