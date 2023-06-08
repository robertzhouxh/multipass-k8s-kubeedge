cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

# ----------------------------------------------------------------
# use google registry
## curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
## cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
## deb https://apt.kubernetes.io/ kubernetes-xenial main
## EOF
## sudo apt-get -o Acquire::http::proxy="http://10.1.105.135:8123" update

# -----------------------------------------------------------------
# use aliyun registry
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF 
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
sudo apt-get update

# ------------------------------------------------------------------
# install kubeadm, kubelet, kubectl
# 查询有哪些版本
# apt-cache madison kubeadm
#sudo apt-get install -y kubelet=1.23.4-00 kubeadm=1.23.4-00 kubectl=1.23.4-00
sudo apt-get install -y kubelet=1.23.17-00 kubeadm=1.23.17-00 kubectl=1.23.17-00

sudo apt-mark hold kubelet kubeadm kubectl

# completion
source <(kubectl completion bash)
source <(kubeadm completion bash)

sudo systemctl daemon-reload
sudo systemctl restart kubelet
