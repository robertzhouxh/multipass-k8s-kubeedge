# k8s 环境部署
## Step1.macos host 管理虚拟机生命周期
```
cd multipass-kubernetes/multipass

#创建虚拟机
./launch-2vm.sh

#销虚拟机
./destroy.sh
```
## Step2.Master节点安装k8s
### 基础套件
```
multipass shell master
sudo -i
git clone https://github.com/robertzhouxh/multipass-kubernetes
cd multipass-kubernetes/cks-master
./containerd.sh
./docker.sh
./install.sh

// 记录
kubeadm join 192.168.64.56:6443 --token a3g8ta.wpxwlrozkq6dzn22 \
	--discovery-token-ca-cert-hash sha256:291fa76a6401a544bc66f32560b4a17e808e1359ad8cde535a56e8d0f2c65646 

```

### 网络插件
```
--------------------------------------------------------------------------------------
1. install flannel
参考： 不建议把 flannel pod 调度到边缘节点
//https://github.com/kubeedge/kubeedge/issues/2677
//https://github.com/kubeedge/kubeedge/issues/4521
//https://docs.openeuler.org/zh/docs/22.09/docs/KubeEdge/KubeEdge%E9%83%A8%E7%BD%B2%E6%8C%87%E5%8D%97.html

wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-arm64-v1.3.0.tgz
mkdir -p /opt/cni/bin
tar xf cni-plugins-linux-arm64-v1.3.0.tgz -C /opt/cni/bin
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f kube-flannel.yml

// disable flannel in edge node, because it connect to kube-apiserver directly.
kubectl edit ds -n kube-system kube-flannel-ds
...
spec:
  ...
  template:
    ...
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
+             - key: node-role.kubernetes.io/agent
+               operator: DoesNotExist

// 验证
kubectl get pods -n kube-flannel

kc edit cm -nkube-system kube-proxy
 ...
 kubeconfig.conf: |-
   apiVersion: v1
   kind: Config
   clusters:
   - cluster:
       certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
       server: http://127.0.0.1:10550
     name: default
 ...

// 卸载
kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

// on node
ifconfig cni0 down
ip link delete cni0
ifconfig flannel.1 down
ip link delete flannel.1
rm -rf /var/lib/cni/
rm -f /etc/cni/net.d/*

注：执行完上面的操作，重启kubelet

--------------------------------------------------------------------------------------
2. install weave
参考：https://github.com/weaveworks/weave/issues/3976
amd64: kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
arm64: kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml

kubectl get pods -n kube-system
kubectl delete ds weave-net -n kube-system


--------------------------------------------------------------------------------------
3. install calico: https://docs.tigera.io/calico/latest/about/

wget https://docs.projectcalico.org/v3.20/manifests/calico.yaml --no-check-certificate
#把pod所在网段改成kubeadm init时选项--pod-network-cidr所指定的网段
#直接用vim编辑打开此文件查找192，按如下标记进行修改：

# no effect. This should fall within `--cluster-cidr`.
# - name: CALICO_IPV4POOL_CIDR
#   value: "192.168.0.0/16"
               |
               v
# no effect. This should fall within `--cluster-cidr`.
- name: CALICO_IPV4POOL_CIDR
  value: "10.244.0.0/16"


#查看此文件用哪些镜像：
grep image calico.yaml

   image: docker.io/calico/cni:v3.20.6
   image: docker.io/calico/pod2daemon-flexvol:v3.20.6
   image: docker.io/calico/node:v3.20.6
   image: docker.io/calico/kube-controllers:v3.20.6

#换成自己的版本
for i in calico/cni:v3.20.6 calico/pod2daemon-flexvol:v3.20.6 calico/node:v3.20.6 calico/kube-controllers:v3.20.6 ; do docker pull $i ; done

kubectl apply -f calico.yaml
```
### 去掉污点
```
kubectl describe nodes master | grep Taints
kubectl taint node master node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/master-
```
## Step3.Worker节点Join
```
multipass shell e-worker

git clone https://github.com/robertzhouxh/multipass-kubernetes
./install-all.sh

kubeadm join 192.168.64.55:6443 --token pitfej.61efpxyer26iv7zo \
	--discovery-token-ca-cert-hash sha256:978db90c12ee512df0d6f4bbb83bb78cab97abd6ae52a760343cf793bd87ec77 
```

## Step4.Master节点安装metrics-server 
### 安装 metrics-server 
```
1. 使用官方镜像地址直接安装
curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
  | sed -e "s|\(\s\+\)- args:|\1- args:\n\1  - --kubelet-insecure-tls|" | kubectl apply -f -

2. 使用自定义镜像地址安装
curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
  | sed \
    -e "s|\(\s\+\)- args:|\1- args:\n\1  - --kubelet-insecure-tls|" \
    -e "s|registry.k8s.io/metrics-server|registry.cn-hangzhou.aliyuncs.com/google_containers|g" \
  | kubectl apply -f -

3. 手动
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
vi component.yaml

修改镜像地址： sed -i 's/registry.k8s.io\/metrics-server/registry.cn-hangzhou.aliyuncs.com\/google_containers/g' metrics-server-components.yaml
修改启动参数： args添加tls证书配置选项： - --kubelet-insecure-tls
kubectl apply -f component.yaml
kubectl get deployments metrics-server -n kube-system

3. 查看集群指标信息
kubectl top nodes
kubectl top pods -n kube-system

```

### 删除 metrics-server

```
kubectl delete ServiceAccount metrics-server -n kube-system
kubectl delete ClusterRoleBinding metrics-server:system:auth-delegator -n kube-system
kubectl delete RoleBinding metrics-server-auth-reader -n kube-system
kubectl delete ClusterRole system:metrics-server -n kube-system
kubectl delete  ClusterRoleBinding system:metrics-server -n kube-system
kubectl delete  APIService v1beta1.metrics.k8s.io -n kube-system
kubectl delete Service metrics-server -n kube-system
kubectl delete Deployment metrics-server -n kube-system
```

## Step5.Master 节点可视化管理
```
sudo docker run -d \
  --restart=unless-stopped \
  --name=kuboard \
  -p 9090:80/tcp \
  -p 10081:10081/tcp \
  -e KUBOARD_ENDPOINT="http://192.168.64.56:80" \
  -e KUBOARD_AGENT_SERVER_TCP_PORT="10081" \
  -v /root/kuboard-data:/data \
  swr.cn-east-2.myhuaweicloud.com/kuboard/kuboard:v3

http://192.168.64.56:9090/sso/auth/default?req=zbxgpuqrf3ajt3tx5clazsd6k
用户名： admin
密码： Kuboard123
```
# kubeedge v1.13.0 安装
## 云端-Master节点
```
multipass shell master

//因为cloudcore没有污点容忍，确保master节点已经去掉污点
wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/
keadm init --advertise-address=192.168.64.56 --kube-config=$HOME/.kube/config --kubeedge-version=1.13.0

//check
netstat -tpnl | grep cloudcore
kubectl get pod -n kubeedge

// reboot cloudcore
systemctl restart cloudcore.service

// 获取token
keadm gettoken
```

注： 如果因为网络原因导致初始化失败，则可以提前把相关文件下载到/etc/kubeedge/
- kubeedge-v1.13.0-linux-arm64.tar.gz(https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/kubeedge-v1.13.0-linux-arm64.tar.gz)
- cloudcore.service(https://raw.githubusercontent.com/kubeedge/kubeedge/master/build/tools/cloudcore.service)
- weave 网络插件问题：https://github.com/kubeedge/kubeedge/issues/4161

## 边端-Worker节点

```
multipass shell e-node
------------------------  可选操作  ------------------------------
设置密码: sudo passwd ubuntu
ssh 开启用户名密码登录
vi /etc/ssh/sshd_config
PermitRootLogin yes
    PasswordAuthentication yes
------------------------------------------------------------------

git clone https://github.com/robertzhouxh/multipass-kubernetes
cd multipass-kubernetes/edge-worker
./docker.sh

wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/


keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=$(keadm gettoken)  --edgenode-name=e-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock

eg:
keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=34b265f92b2c30025c9ecafa0d372db7d7ae8d0a64da9d5a8fd1c96fbb5ab972.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2ODYyMDMxMjV9.J9P__HaSFqiQovL-uNUk9NvOR-oqxFtpS6n8R35Em0I --edgenode-name=e-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock


// reboot cloudcore
systemctl restart cloudcore.service
systemctl status edgecore.service
journalctl -u edgecore.service -f
```

注：
如果要使用containerd, 则要打开 cri，参考 https://github.com/kubeedge/kubeedge/issues/4621
开启 edgeStream，
  - 编辑 /etc/kubeedge/config/edgecore.yaml 文件
  - 找到 edgeStream字段，将 enable: false 改为 enable: true
  - 保存文件，重启 edgecore 服务，systemctl restart edgecore.service

### 卸载EdgeCore

edgecore 服务正常： keadm reset
edgecore 服务退出： systemctl disable edgecore.service && rm /etc/systemd/system/edgecore.service && rm -r /etc/kubeedge && docker rm -f mqtt
on Master  删节点： kubectl delete node e-node

## 定位问题

```
// on master:
查看k8s 运行日志命令, 这个比较有用，在k8s 启动、kubeadm init、kubeadm join 阶段可以辅助分析问题。 journalctl -xefu kubelet 
查看驱动： systemctl show --property=Environment kubelet |cat
重启:     systemctl restart kubelet
启动:     systemctl start kubelet
停止:     systemctl stop kubelet
开机自启:  systemctl enable kubelet

dashboard 获取token: kubectl describe secret admin-user -n kubernetes-dashboard
kubeadm 重置， kubeadm init 命令报错，修复问题后需要重新进行 init 操作： kubeadm reset

查看存在token: kubeadm token list
生成永久token: kubeadm token create --ttl 0
测试 coredns： kubectl run busybox --image busybox: 1.28 -restart=Never --rm -it busybox -- sh
              nslookup my-web.default.sc.cluster.local



kubectl get pods -o wide -n kube-system
kubectl get pod podName  -o yaml | grep phase
kubectl describe pod PodName -n kube-system

// on edge
flannel 错误

https://github.com/kubeedge/kubeedge/issues/4691
TOKEN=`kubectl get secret -nkubeedge tokensecret -o=jsonpath='{.data.tokendata}' | base64 -d`
keadm join \
    --kubeedge-version=v1.13.0 \
    --cloudcore-ipport=192.168.50.12:10000 \
	--token=$TOKEN \
	--cgroupdriver=systemd \
	--runtimetype=docker \
	--remote-runtime-endpoint="unix:///var/run/cri-dockerd.sock"


systemctl status edgecore.service
systemctl restart edgecore.service
journalctl -u edgecore.service -f
journalctl -u edgecore.service -xe
    
# 杀掉当前edgecore进程
pkill edgecore

# 重启edgecore
systemctl restart edgecore
```

## 边云-Edgemesh
### 前置准备

```
步骤1: 去除 K8s master 节点的污点
kubectl taint nodes --all node-role.kubernetes.io/master-

步骤2: 给 Kubernetes API 服务添加过滤标签
kubectl label services kubernetes service.edgemesh.kubeedge.io/service-proxy-name=""

步骤3: 启用 KubeEdge 的边缘 Kube-API 端点服务

3.1 在云端，开启 dynamicController 模块，配置完成后，需要重启 cloudcore

1)keadm安装的通过以下指令修改： kubectl edit cm -n kubeedge cloudcore
//修改
modules:
  ...
  dynamicController:
    enable: true
...

// 执行完后,检查一下
// 如果不放心，直接去kuboard在kubeedge上把cloudcore删除掉，然后会根据新的模板创建新的容器
kubectl describe cm -n kubeedge cloudcore

2) 其他方式安装的
vim /etc/kubeedge/config/cloudcore.yaml
modules:
  ...
  dynamicController:
    enable: true
  ...

// 重启cloudcore
pkill cloudcore
systemctl restart cloudcore

3.2: 在边缘，打开 metaServer 模块，完成后重启 edgecore
vim /etc/kubeedge/config/edgecore.yaml
  metaManager:
    metaServer:
+     enable: true

添加 edgemesh commonconfig 信息：
$ vim /etc/kubeedge/config/edgecore.yaml

edged:
  ...
  tailoredKubeletConfig:
    ...
+   clusterDNS:
+   - 169.254.96.16
    clusterDomain: cluster.local


//重启edgecore
pkill edgecore
systemctl restart edgecore


步骤4: 最后，在边缘节点，测试边缘 Kube-API 端点功能是否正常
curl 127.0.0.1:10550/api/v1/services

```

### 安装

```

git clone https://github.com/kubeedge/edgemesh.git
cd edgemesh

// 安装 crd
kubectl apply -f build/crds/istio/

// 部署edgemesh agent
请根据你的 K8s 集群设置 relayNodes，并重新生成 PSK 密码
vim build/agent/resources/04-configmap.yaml

   relayNodes:
   - nodeName: master
    advertiseAddress:
    - 192.168.64.56
    - nodeName: kubeedge
    advertiseAddress:
    - 172.23.70.34
    - 172.23.70.12

+   psk: $(openssl rand -base64 32)


kubectl apply -f build/agent/resources/


验证
kubectl get all -n kubeedge -o wide
```

    
