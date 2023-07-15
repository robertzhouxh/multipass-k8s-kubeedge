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

./containerd.sh
./install.sh

crictl config runtime-endpoint /run/containerd/containerd.sock
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
### 安装 metrics-server
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
  
  3) 手动（hostNetwork: true） 设置 hostNetwork=true 参考：https://support.huaweicloud.com/usermanual-cce/cce_10_0402.html
  // Kubernetes支持Pod直接使用主机（节点）的网络，当Pod配置为hostNetwork: true时，在此Pod中运行的应用程序可以直接看到Pod所在主机的网络接口。
  // 由于使用主机网络，访问Pod就是访问节点，要注意放通节点安全组端口，否则会出现访问不通的情况。
  wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl apply -f components.yaml
  kubectl get deployments metrics-server -n kube-system
  kubectl patch deploy metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},{"op":"add","path":"/spec/template/spec/ostNetwork","value":true}]'

2. 验证
kubectl top nodes
kubectl top pods -n kube-system 

3. 删除 metrics-server
kubectl delete -f components.yaml

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
systemctl restart docker kubelet

rm -rf $HOME/.kube/config
rm -f /etc/kubernetes/kubelet.conf
rm -f /etc/kubernetes/pki/ca.crt 

iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
```
# kubeedge 部署
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
wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/

// iptablesmanager:v1.13.0 镜像版本错误： https://github.com/kubeedge/kubeedge/pull/4620
docker pull kubeedge/cloudcore:v1.13.0
docker pull kubeedge/iptablesmanager:v1.13.0
docker tag kubeedge/iptablesmanager:v1.13.0 kubeedge/iptables-manager:v1.13.0

//keadm init --advertise-address=192.168.64.56 --kube-config=$HOME/.kube/config  --profile version=v1.13.0 --set iptablesManager.mode="external"
keadm init --advertise-address=192.168.64.64 --kube-config=$HOME/.kube/config  --profile version=v1.13.0


// 打开转发路由
export CLOUDCOREIPS="192.168.64.64"
iptables -t nat -A OUTPUT -p tcp --dport 10350 -j DNAT --to $CLOUDCOREIPS:10003
iptables -t nat -A OUTPUT -p tcp --dport 10351 -j DNAT --to $CLOUDCOREIPS:10003

// 验证
netstat -nltp | grep cloudcore

// 重启 cloudcore
pkill cloudcore

// logs
kubectl logs -f  cloudcore-54b85b8757-hvt4n -n kubeedge
```


注： 

如果因为网络原因导致初始化失败，则可以提前把相关文件下载到/etc/kubeedge/
- cloudStream 在 v1.30.0 中云端已默认开启，无需手动开启
- kubeedge-v1.13.0-linux-arm64.tar.gz(https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/kubeedge-v1.13.0-linux-arm64.tar.gz)
- cloudcore.service(https://raw.githubusercontent.com/kubeedge/kubeedge/master/build/tools/cloudcore.service)
- weave 网络插件问题：https://github.com/kubeedge/kubeedge/issues/4161

## 边缘节点

```
multipass shell mec-node

sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sudo sysctl -p | grep ip_forward

git clone https://github.com/robertzhouxh/multipass-k8s-kubeedge
cd mec-node
./docker.sh

wget https://github.com/kubeedge/kubeedge/releases/download/v1.13.0/keadm-v1.13.0-linux-arm64.tar.gz
tar xzvf keadm-v1.13.0-linux-arm64.tar.gz && cp keadm-v1.13.0-linux-arm64/keadm/keadm /usr/sbin/

keadm join --cloudcore-ipport=192.168.64.56:10000 --kubeedge-version=1.13.0 --token=$(keadm gettoken)  --edgenode-name=mec-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock

eg:
docker pull eclipse-mosquitto:1.6.15
docker pull kubeedge/installation-package:v1.13.0
docker pull kubeedge/pause:3.6 

keadm join --cloudcore-ipport=192.168.64.64:10000 --kubeedge-version=1.13.0 --token=90f670cea3f1ce2311c79144840bceebc167d832549200c6ea51d899f7112e44.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2ODY0NTc4ODd9.aTmHkM1Ubov2NGPTH_J-QhoL8e68NkzL59ENOUN2GfI --edgenode-name=mec-node --runtimetype=docker --remote-runtime-endpoint unix:///run/containerd/containerd.sock

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

# 可视化管理 
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

