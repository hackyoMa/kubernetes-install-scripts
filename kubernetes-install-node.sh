#!/bin/sh

echo "sample: "
echo "  address: 192.168.137.48:6443"
echo "  token: o58yu1.qh2axhqeq4fnuwsc"
echo "  cert hash: sha256:0c5e3441cac5ac4e7ae5dd7fc0bfd61779d3ffcf52451ccc7eba212cde065292"

read -p "Please enter the address: " hackyoAddress
if [ -z "$hackyoAddress" ]; then
  echo "Error: Please enter the address"
  exit
fi

read -p "Please enter token: " hackyoToken
if [ -z "$hackyoToken" ]; then
  echo "Error: Please enter token"
  exit
fi

read -p "Please enter cert hash: " hackyoCertHash
if [ -z "$hackyoCertHash" ]; then
  echo "Error: Please enter cert hash"
  exit
fi

#设置阿里云yum源
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
rm -rf /var/cache/yum && yum makecache && yum -y update

#安装依赖
yum install -y epel-release conntrack ipvsadm ipset jq sysstat curl iptables libseccomp

#关闭防火墙
systemctl stop firewalld && systemctl disable firewalld
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat && iptables -P FORWARD ACCEPT

#关闭SELinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

#关闭swap分区
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#加载内核模块
modprobe br_netfilter
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack_ipv4
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
modprobe -- br_netfilter
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules

#设置内核参数
cat << EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
sysctl -p /etc/sysctl.d/kubernetes.conf

#安装Docker
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
yum install -y docker-ce
systemctl start docker
systemctl enable docker

#修改Docker配置
sed -i "13i ExecStartPost=/usr/sbin/iptables -P FORWARD ACCEPT" /usr/lib/systemd/system/docker.service
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://bk6kzfqm.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
systemctl daemon-reload
systemctl restart docker

#安装kubeadm和kubelet
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
yum makecache fast
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet

#从阿里云拉取镜像
kubeadm config images list | sed -e 's/^/docker pull /g' -e 's#k8s.gcr.io#registry.aliyuncs.com/google_containers#g' | sh -x
docker images | grep registry.aliyuncs.com/google_containers | awk '{print "docker tag",$1":"$2,$1":"$2}' | sed -e 's/registry.aliyuncs.com\/google_containers/k8s.gcr.io/2' | sh -x
docker images | grep registry.aliyuncs.com/google_containers | awk '{print "docker rmi """$1""":"""$2}' | sh -x

#使用kubeadm init初始化节点
kubeadm join $hackyoAddress --token $hackyoToken --discovery-token-ca-cert-hash $hackyoCertHash
unset hackyoAddress
unset hackyoToken
unset hackyoCertHash
