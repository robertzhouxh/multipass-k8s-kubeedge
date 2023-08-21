# k8s 部署
## Step1.macos host 管理虚拟机生命周期
```
cd multipass

// 设置驱动
multipass set local.driver=qemu

// 设置桥接网络
multipass networks

// 输出大概是这样的
    Name     Type         Description
    bridge0  bridge       Network bridge with en2, en3, en4, en5
    en0      ethernet     Ethernet
    en1      wifi         Wi-Fi
    en2      thunderbolt  Thunderbolt 1
    en3      thunderbolt  Thunderbolt 2
    en4      thunderbolt  Thunderbolt 3
    en5      thunderbolt  Thunderbolt 4

// 选择你的有线网卡名字，这里是en0, 当然你的 macos 需要接入网线，无线网卡可能不能好好工作
// 配置桥接网络
multipass set local.bridged-network=en0

// 启动虚拟机
multipass launch --name aibox02 -c 2 -m 2G jammy --disk 20G --bridged --cloud-init systemd-resolved.yaml 

或者指定要桥接的网卡 en0
multipass launch --name aibox01 -c 2 -m 2G jammy --disk 20G --cloud-init systemd-resolved.yaml --network en0

// 关于DNS: /etc/resolv.conf文件仍然存在，但它是由systemd-resolved服务控制的符号链接，不应手动对其进行编辑。
// systemd-resolved是为本地服务和应用程序提供DNS名称解析的服务，可以使用Netplan进行配置，Netplan是Ubuntu 22.04的默认网络管理工具。
// Netplan配置文件存储在/etc/netplan目录。该文件名为01-netcfg.yaml或50-cloud-init.yaml
// 这些文件使您可以配置网络接口，我们通常称为网卡，包括IP地址，网关，DNS域名服务器等。

sudo vim 50-cloud-init.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens3:    // 必须修改本教程中接口名称ens3为你的计算机接口名称:enp0s2。
      dhcp4: true
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]

// 如果您想使用Cloudflare的DNS服务器，则可以将nameservers的addresses行更改为
 nameservers:
          addresses: [1.1.1.1, 1.0.0.1]

// 然后运行命令sudo netplan apply 应用更改。
// 此外，还有一些应用程序依然使用/etc/resolv.conf的配置文件的DNS地址进行域名的解释，因此你还需要修改/etc/resolv.conf文件。
// 选择和宿主机 en0 网段的那个地址对应的ip所在网卡: enp0s2
sudo netplan apply
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

//创建虚拟机
./launch-2vm.sh

销虚拟机
./destroy.sh
```
## Step2.Master节点安装/卸载 k8s
### 基础套件
```
multipass shell master
sudo -i
git clone -b kueedge-1.4.0 https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd multipass-k8s-kubeedge/master-node

./containerd.sh
crictl config runtime-endpoint /run/containerd/containerd.sock
./install.sh

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
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-arm64-v1.3.0.tgz

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

```
### 去掉污点
```
kubectl describe nodes master | grep Taints
kubectl taint node master node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/master-

```
## Step3.[可选]k8s节点join
```
multipass shell e-worker
git clone https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd multipass-k8s-kubeedge/k8s-node
./install-all.sh

//on master node:
kubeadm token create
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^ .* //'

kubeadm join 192.168.64.64:6443 --token zarmgo.vnwbnnh92un15qsj --discovery-token-ca-cert-hash sha256:30357707e093c2f74e9563d50dfb7b8c584d6983b775b5afe82684739a4a0f50
```
## 重置K8S
```
swapoff -a
kubeadm reset
systemctl daemon-reload
systemctl restart kubelet

rm -rf $HOME/.kube/config
rm -f /etc/kubernetes/kubelet.conf
rm -f /etc/kubernetes/pki/ca.crt 

iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
```
# kubeedge 部署(https://release-1-14.docs.kubeedge.io/zh/docs/setup/install-with-keadm)
## 云端节点
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
wget https://github.com/kubeedge/kubeedge/releases/download/v1.14.1/keadm-v1.14.1-linux-arm64.tar.gz
tar xzvf keadm-v1.14.1-linux-arm64.tar.gz && cp keadm-v1.14.1-linux-arm64/keadm/keadm /usr/sbin/
keadm init --advertise-address=192.168.64.81

// 打开路由转发以支持 kubectl logs 
export CLOUDCOREIPS="192.168.64.81"
echo $CLOUDCOREIPS
iptables -t nat -A OUTPUT -p tcp --dport 10350 -j DNAT --to $CLOUDCOREIPS:10003
mkdir -p /etc/kubeedge/ 
wget https://raw.githubusercontent.com/kubeedge/kubeedge/master/build/tools/certgen.sh
cp certgen.sh /etc/kubeedge/ 

// 为 CloudStream 生成证书
/etc/kubeedge/certgen.sh stream

// 设置全局环境变量
export CLOUDCOREIPS="192.168.64.81"

// 验证
netstat -nltp | grep cloudcore

// 重启 cloudcore
pkill cloudcore

// logs
kubectl logs -f  cloudcore-54b85b8757-hvt4n -n kubeedge
```

注： 
如果因为网络原因导致初始化失败，则可以提前把相关文件下载到/etc/kubeedge/
- kubeedge-v1.14.1-linux-arm64.tar.gz(https://github.com/kubeedge/kubeedge/releases/download/v1.14.1/kubeedge-v1.14.1-linux-arm64.tar.gz)
- cloudcore.service(https://raw.githubusercontent.com/kubeedge/kubeedge/master/build/tools/cloudcore.service)

## 边缘节点（临时fq: /etc/hosts 185.199.108.133 raw.githubusercontent.com, 140.82.112.3 github.com）
参考 https://github.com/kubeedge/kubeedge/issues/4589
参考 https://github.com/containerd/containerd/blob/main/docs/getting-started.md#step-3-installing-cni-plugins 安装containerd+cni

```
multipass shell mec-node

sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sudo sysctl -p | grep ip_forward

git clone -b kueedge-1.4.0 https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd mec-node
./containerd.sh

wget https://github.com/kubeedge/kubeedge/releases/download/v1.14.1/keadm-v1.14.1-linux-arm64.tar.gz
tar xzvf keadm-v1.14.1-linux-arm64.tar.gz && cp keadm-v1.14.1-linux-arm64/keadm/keadm /usr/sbin/

keadm join --cloudcore-ipport=192.168.64.81:10000 --kubeedge-version=1.14.1 --token=$(keadm gettoken)  --edgenode-name=mec-node 

2d336b44a30f886bf7d9b378cf63d09a9efb984c645c7ca273d5a02e2ce90b85.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2OTI2MjY3Nzd9.s7Lmmvruhv73KRiZ283kkyTiwndFn-yzOxCvH8jC6K8

// reboot edgecore
systemctl restart edgecore.service
systemctl status edgecore.service
journalctl -u edgecore.service -f
```

### 卸载EdgeCore

    edgecore 服务正常： keadm reset
    edgecore 服务退出： systemctl disable edgecore.service && rm /etc/systemd/system/edgecore.service && rm -r /etc/kubeedge && docker rm -f mqtt
    on Master  删节点： kubectl delete node mec-node

## Edgemesh
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

### 可视化管理 
```
sudo docker run -d \
  --restart=unless-stopped \
  --name=kuboard \
  -p 9090:80/tcp \
  -p 10081:10081/tcp \
  -e KUBOARD_ENDPOINT="http://192.168.64.64:80" \
  -e KUBOARD_AGENT_SERVER_TCP_PORT="10081" \
  -v /root/kuboard-data:/data \
  swr.cn-east-2.myhuaweicloud.com/kuboard/kuboard:v3

http://192.168.64.64:9090
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

https://www.cnblogs.com/hahaha111122222/p/16445834.html
要使用systemdcgroup驱动程序，请在 /etc/containerd/config.toml 中进行设置plugins.cri.systemd_cgroup = true

For containerd:

$ nerdctl ps -a --namespace k8s.io
$ nerdctl rm 84d2a565793ce8ed658488500612287840f4a81225491611c1ee21dc7f4162cc --namespace k8s.io

+ kubectl get cm -n kube-system
+ kubectl edit cm kubelet-config-1.22 -n kube-system
+ nerdctl info | grep system

## Master

```
    kubeadm init、kubeadm join 阶段可以辅助分析问题: journalctl -xefu kubelet 
    systemctl restart/start/stop kubelet
    开机自启:  systemctl enable kubelet
    dashboard 获取token: kubectl describe secret admin-user -n kubernetes-dashboard
    查看存在token: kubeadm token list
    生成永久token: kubeadm token create --ttl 0

    测试 coredns： 


kubectl exec -it podName  -c  containerName -n namespace -- shell comand
kubectl run busybox --image busybox -restart=Never --rm -it busybox -- sh nslookup my-web.default.sc.cluster.local

kubectl get node --show-labels
kubectl label nodes nodeName LabelKey=LabelValue
kbectl label nodes nodeName Labelkey-

eg
kubectl label nodes mec-node node-meta.kubernetes.io/insid=ironman
kubectl label nodes mec-node node-meta.kubernetes.io-


kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: busybox-sleep
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-meta.kubernetes.io/insid
            operator: In
            values:
            - ironman
  containers:
  - name: busybox
    image: busybox:1.36
    args:
    - sleep
    - "1000000"
EOF

```
kubectl get pod busybox-sleep
kubectl exec --stdin --tty busybox-sleep -- /bin/sh

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

