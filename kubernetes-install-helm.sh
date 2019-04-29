#!/bin/sh

#生成证书
openssl genrsa -out ca.key.pem 4096
openssl req -key ca.key.pem -new -x509 -days 7300 -sha256 -out ca.cert.pem -extensions v3_ca -batch
openssl genrsa -out tiller.key.pem 4096
openssl genrsa -out helm.key.pem 4096
openssl req -key tiller.key.pem -new -sha256 -out tiller.csr.pem -batch
openssl req -key helm.key.pem -new -sha256 -out helm.csr.pem -batch
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in tiller.csr.pem -out tiller.cert.pem -days 7300
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in helm.csr.pem -out helm.cert.pem -days 7300

#安装helm
curl -O https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz
tar -zxvf helm-v2.13.1-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
ln -s /usr/local/bin/helm /usr/bin/helm
rm -f helm-v2.13.1-linux-amd64.tar.gz && rm -rf linux-amd64/

#配置TLS
mkdir -p $(helm home)
cp ca.cert.pem $(helm home)/ca.pem
cp helm.cert.pem $(helm home)/cert.pem
cp helm.key.pem $(helm home)/key.pem

#设置授权
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

#初始化helm
helm init \
--override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}' \
--tiller-image=registry.aliyuncs.com/google_containers/tiller:v2.13.1 \
--tiller-tls \
--tiller-tls-verify \
--tiller-tls-cert=tiller.cert.pem \
--tiller-tls-key=tiller.key.pem \
--tls-ca-cert=ca.cert.pem \
--service-account=tiller \
--stable-repo-url=https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
