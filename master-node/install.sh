cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

sudo apt-get update && sudo apt-get install -y apt-transport-https curl

# ----------------------------------------------------------------
# use google registry
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
# cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
# deb https://apt.kubernetes.io/ kubernetes-xenial main
# EOF
# sudo apt-get -o Acquire::http::proxy="http://10.1.105.135:8123" update


# -------------------------------------------------------------------------------------
# use aliyun registry
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF 
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
sudo apt-get update

# -------------------------------------------------------------------------------------
# install kubeadm, kubelet, kubectl
# 查询有哪些版本
# apt-cache madison kubeadm
#sudo apt-get install -y kubelet=1.20.0-00 kubeadm=1.20.0-00 kubectl=1.20.0-00
#sudo apt-get install -y kubelet=1.23.4-00 kubeadm=1.23.4-00 kubectl=1.23.4-00
#sudo apt-get install -y kubelet=1.23.15-00 kubeadm=1.23.15-00 kubectl=1.23.15-00
sudo apt-get install -y kubelet=1.22.17-00 kubeadm=1.22.17-00 kubectl=1.22.17-00

sudo apt-mark hold kubelet kubeadm kubectl

# completion
source <(kubectl completion bash)
source <(kubeadm completion bash)

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# ---------------------------------------------------------------------------------------
# install k8s from aliyun repository
# kubeadm init
echo "===> 开始安装 K8S"
echo ""

kubeadm init \
  --image-repository registry.aliyuncs.com/google_containers \
  --service-cidr=10.96.0.0/12 \
  --pod-network-cidr=10.244.0.0/16 \
  --kubernetes-version v1.22.17 \
  --cri-socket=unix:///run/containerd/containerd.sock

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "K8S 安装结束！"
echo ""
