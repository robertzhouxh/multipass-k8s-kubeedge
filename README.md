# k8s 部署
## Step1.macos host 管理虚拟机生命周期
```
cd multipass

//创建虚拟机
./launch-2vm.sh

注：  en0 表示要桥接的网卡
multipass launch --name o-worker -c 2 -m 2G jammy --disk 30G --cloud-init systemd-resolved.yaml--network en0

销虚拟机
./destroy.sh
```
## Step2.Master节点安装/卸载 k8s
### 基础套件
```
multipass shell master
sudo -i
git clone https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd multipass-k8s-kubeedge/master-node
./install-all

// 记录
kubeadm join 192.168.64.56:6443 --token y2mayd.pqd1cia9o8as336t \
	--discovery-token-ca-cert-hash sha256:2645e6fd8b3d3de42e96dd12dc0d232f3a74527b4c73c35c7311d3dea83c2f22 
```

### 网络插件(建议安装 flannel)
```
--------------------------------------------------------------------------------------
1. install flannel
参考： 不建议把 flannel pod 调度到边缘节点 disable flannel in edge node, because it connect to kube-apiserver directly.

//https://github.com/kubeedge/kubeedge/issues/2677
//https://github.com/kubeedge/kubeedge/issues/4521
//https://docs.openeuler.org/zh/docs/22.09/docs/KubeEdge/KubeEdge%E9%83%A8%E7%BD%B2%E6%8C%87%E5%8D%97.html
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-arm64-v1.3.0.tgz
mkdir -p /opt/cni/bin
tar xf cni-plugins-linux-arm64-v1.3.0.tgz -C /opt/cni/bin
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

vim kube-flannel.yml
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

kubectl apply -f kube-flannel.yml

// 验证
kubectl get pods -n kube-flannel

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
systemctl restart kubelet

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
## Step3.Master节点安装 metrics-server
```
1. 安装

  1) 使用官方镜像地址直接安装
  curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
    | sed -e "s|\(\s\+\)- args:|\1- args:\n\1  - --kubelet-insecure-tls|" | kubectl apply -f -
  
  2) 使用自定义镜像地址安装
  curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
    | sed \
      -e "s|\(\s\+\)- args:|\1- args:\n\1  - --kubelet-insecure-tls|" \
      -e "s|registry.k8s.io/metrics-server|registry.cn-hangzhou.aliyuncs.com/google_containers|g" \
    | kubectl apply -f -
  
  3) 手动（hostNetwork: true）
  wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl apply -f component.yaml
  kubectl get deployments metrics-server -n kube-system
  kubectl patch deploy metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},{"op":"add","path":"/spec/template/spec/hostNetwork","value":true}]'


2. 验证
kubectl top nodes
kubectl top pods -n kube-system 

3. 删除 metrics-server
kubectl delete -f components.yaml

```
## Step4.Worker节点 Join
```
multipass shell e-worker

git clone https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd multipass-k8s-kubeedge/worker-node
./install-all.sh

kubeadm join 192.168.64.55:6443 --token pitfej.61efpxyer26iv7zo \
	--discovery-token-ca-cert-hash sha256:978db90c12ee512df0d6f4bbb83bb78cab97abd6ae52a760343cf793bd87ec77 
```
## 重置K8S
```
swapoff -a
kubeadm reset
systemctl daemon-reload
systemctl restart docker kubelet

rm -rf $HOME/.kube/config
rm -f /etc/kubernetes/kubelet.conf
rm -f /etc/kubernetes/pki/ca.crt 

iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
```
# kubeedge 部署
## 云端-Master节点
```
multipass shell master

/--------------------------  因为cloudcore没有污点容忍，确保master节点已经去掉污点  -------------------------------------\
// 边缘节点上不执行kube-proxy
kubectl edit daemonsets.apps -n kube-system kube-proxy

affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/edge
          operator: DoesNotExist


或者采用以下patch
kubectl patch daemonset kube-proxy -n kube-system -p '{"spec": {"template": {"spec": {"affinity": {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": {"nodeSelectorTerms": [{"matchExpressions": [{"key": "node-role.kubernetes.io/edge", "operator": "DoesNotExist"}]}]}}}}}}}'


// install kubeedge
wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/

// iptablesmanager:v1.13.0 镜像版本错误： https://github.com/kubeedge/kubeedge/pull/4620
docker pull kubeedge/kubeedge/cloudcore:v1.13.0
docker pull kubeedge/iptablesmanager:v1.13.0
docker tag kubeedge/iptablesmanager:v1.13.0 kubeedge/iptables-manager:v1.13.0

//keadm init --advertise-address=192.168.64.56 --kube-config=$HOME/.kube/config  --profile version=v1.13.0 --set iptablesManager.mode="external"
keadm init --advertise-address=192.168.64.56 --kube-config=$HOME/.kube/config  --profile version=v1.13.0


// 打开转发路由
export CLOUDCOREIPS="192.168.64.56"
iptables -t nat -A OUTPUT -p tcp --dport 10350 -j DNAT --to $CLOUDCOREIPS:10003
iptables -t nat -A OUTPUT -p tcp --dport 10351 -j DNAT --to $CLOUDCOREIPS:10003

// 验证
netstat -nltp | grep cloudcore

// 重启 cloudcore
pkill cloudcore
```

注： 

如果因为网络原因导致初始化失败，则可以提前把相关文件下载到/etc/kubeedge/
- cloudStream 在 v1.30.0 中云端已默认开启，无需手动开启
- kubeedge-v1.13.0-linux-arm64.tar.gz(https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/kubeedge-v1.13.0-linux-arm64.tar.gz)
- cloudcore.service(https://raw.githubusercontent.com/kubeedge/kubeedge/master/build/tools/cloudcore.service)
- weave 网络插件问题：https://github.com/kubeedge/kubeedge/issues/4161

## 边端-Worker节点（卸载记得master节点上 kubectl delete node e-node）

```
multipass shell e-node

sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sudo sysctl -p | grep ip_forward

git clone https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd edge-node
./docker.sh

wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/

keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=$(keadm gettoken)  --edgenode-name=edge-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock

eg:
docker pull eclipse-mosquitto:1.6.15
docker pull kubeedge/installation-package:v1.13.0
docker pull kubeedge/pause:3.6 

keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=fd18f2a8b740c217a3f0beb79f01bdadd39c696a9cb821ab419b3ebc7c206245.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2ODYzNzgxODZ9.UhU1pMkvXGCF77z5R55GwnMNKTbtucsa157ri7U7R_4 --edgenode-name=e-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock


keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=cfced7937846764a14793faa48b20e32ed6244042df17ad696a876e1c1b96ae9.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2ODYzNzI4MzF9.jhW8ZWhMlQFmQ4qEvE8H3-QNbwY-G5PdBbJcUdzqGWU --edgenode-name=e-worker --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock


// reboot edgecore
systemctl restart edgecore.service
systemctl status edgecore.service
journalctl -u edgecore.service -f
```

注：
1) 如果要使用containerd, 则要打开 cri，参考 https://github.com/kubeedge/kubeedge/issues/4621
2) 边缘节点开启 edgeStream, 支持 metrics-server 获取子节点 cpu, mem 
- vi /etc/kubeedge/config/edgecore.yaml 
  - edgeStream enable: false->true
- systemctl restart edgecore.service

### 卸载EdgeCore

    edgecore 服务正常： keadm reset
    edgecore 服务退出： systemctl disable edgecore.service && rm /etc/systemd/system/edgecore.service && rm -r /etc/kubeedge && docker rm -f mqtt
    on Master  删节点： kubectl delete node e-node

## 边云-Edgemesh
### Master+Node 节点前置条件

    ```
    1. 去除 K8s master 节点的污点
    kubectl taint nodes --all node-role.kubernetes.io/master-

    2: 给 Kubernetes API 服务添加过滤标签
    kubectl label services kubernetes service.edgemesh.kubeedge.io/service-proxy-name=""

    3. 启用 KubeEdge 的边缘 Kube-API 端点服务

    3.1 在云端，开启 dynamicController 模块，配置完成后，需要重启 cloudcore

         1)keadm安装的通过以下指令修改： kubectl edit cm -n kubeedge cloudcore
             dynamicController: 
                 enable: false -> true
         //检查一下， 如果不放心， 直接去kuboard在kubeedge上把cloudcore删掉，然后会根据新的模板创建新的容器
         kubectl describe cm -n kubeedge cloudcore

         2) 其他方式安装的： vim /etc/kubeedge/config/cloudcore.yaml
             dynamicController:
                 enable: true -> true

         // 重启cloudcore
         pkill cloudcore
         systemctl restart cloudcore

    3.2: 在边缘
        打开 metaServer 模块，完成后重启 edgecore
        vim /etc/kubeedge/config/edgecore.yaml
          metaManager:
            metaServer:
        +     enable: true

        添加 edgemesh commonconfig 信息：
        vim /etc/kubeedge/config/edgecore.yaml
        
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
```

在边缘节点，测试边缘 Kube-API 端点功能是否正常
curl 127.0.0.1:10550/api/v1/services

### Master 节点安装
```
git clone https://github.com/kubeedge/edgemesh.git
cd edgemesh

// 安装 crd
kubectl apply -f build/crds/istio/

// 部署edgemesh agent
vim build/agent/resources/04-configmap.yaml

   relayNodes:
   - nodeName: master
    advertiseAddress:
+   - 192.168.64.56
    - nodeName: kubeedge
    #advertiseAddress:
    #- x.x.x.x
    #- a.b.c.d

+   psk: $(openssl rand -base64 32)

kubectl apply -f build/agent/resources/

// 验证
kubectl get all -n kubeedge -o wide
```

# 可视化管理 
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

http://192.168.64.56:9090
用户名： admin
密码： Kuboard123
```

Tricks: 
mac: cat ~/.kube/config | pbcopy

## master 节点操作
```
1. 操作镜像
kubectl exec -n namespace pods-name -it -- /bin/bash

2. 获取日志
kubectl logs -n namespace pods-name

3. 查看配置信息
kubectl describe configmap -n namespace service-name

4. 编辑配置信息
kubectl edit configmap -n namespace service-name

5.根据yaml创建
kubectl create -f name.yaml

6.根据yaml删除
kubectl delete -f name.yaml
    ```
## 定制 Pod 的 DNS 策略

DNS 策略可以逐个 Pod 来设定。目前 Kubernetes 支持以下特定 Pod 的 DNS 策略。 这些策略可以在 Pod 规约中的 dnsPolicy 字段设置：
- Default: Pod 从运行所在的节点继承名称解析配置
- ClusterFirst: 与配置的集群域后缀不匹配的任何 DNS 查询（例如 "www.kubernetes.io"） 都转发到从节点继承的上游名称服务器。集群管理员可能配置了额外的存根域和上游 DNS 服务器。
- ClusterFirstWithHostNet：对于以 hostNetwork 方式运行的 Pod，应显式设置其 DNS 策略 "`ClusterFirstWithHostNet`"。
- None: 此设置允许 Pod 忽略 Kubernetes 环境中的 DNS 设置。Pod 会使用其 `dnsConfig` 字段 所提供的 DNS 设置。

说明：** "Default" 不是默认的 DNS 策略。如果未明确指定 `dnsPolicy`，则使用 "ClusterFirst"。

1. 在 pod 的 yaml 中添加：

```
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

kubectl exec -it pod-name -n namespace -- cat /etc/resolv.conf
nameserver 10.66.0.2 成功


2. 同时使用 hostNetwork 与 coredns 作为 Pod 预设 DNS 配置。

```
cat dns.yml 
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dns-none
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dns
      release: v1
  template:
    metadata:
      labels:
        app: dns
        release: v1
        env: test
    spec:
      hostNetwork: true
      containers:
      - name: dns
        image: registry.cn-beijing.aliyuncs.com/google_registry/myapp:v1
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 80
      dnsPolicy: ClusterFirstWithHostNet
```
kubectl  apply  -f dns,yml

验证dns配置
```
kubectl exec -it   dns-none-86nn874ba8-57sar  -n default -- cat /etc/resolv.conf
nameserver xxx
search default.svc.cluster.local svc.cluster.local cluster.local localdomain
options ndots:5
```

# 定位问题
## Master

```
    kubeadm init、kubeadm join 阶段可以辅助分析问题: journalctl -xefu kubelet 
    systemctl restart/start/stop kubelet
    开机自启:  systemctl enable kubelet
    dashboard 获取token: kubectl describe secret admin-user -n kubernetes-dashboard
    查看存在token: kubeadm token list
    生成永久token: kubeadm token create --ttl 0

    测试 coredns： 
    kubectl run busybox --image busybox:1.28 -restart=Never --rm -it busybox -- sh nslookup my-web.default.sc.cluster.local

    kubectl get pods -o wide -n kube-system
    kubectl get pod podName  -o yaml | grep phase
    kubectl describe pod PodName -n kube-system

```
## 边缘问题
``` 
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

```

