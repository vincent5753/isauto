#!/bin/bash
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
end=$'\e[0m'

echo "${grn}[info]${end} Made by vp@22.12.05"
echo "${grn}[info]${end} update@22.12.13"

# Check if yq is installed
yqpath=/usr/bin/yq
if [ -f "$yqpath" ]; then
    echo "${grn}[info]${end} 於 $yqpath 偵測到已安裝yq"
else
    read -p  "${yel}[info]${end} $yqpath 不存在, 幫你裝個? [y/n] " installyq
    if [ $installyq == "y" ]
    then
        echo "${yel}[info]${end} 為了安裝yq，請輸入目前使用者的密碼(我假設你有sudo權限)"
        sudo echo "${grn}[info]${end} 我有權限惹!"
        YQVERSION=v4.2.0 ; YQBINARY=yq_linux_amd64
        wget --quiet https://github.com/mikefarah/yq/releases/download/${YQVERSION}/${YQBINARY}.tar.gz -O - | tar xz && sudo mv ${YQBINARY} /usr/bin/yq
    else
    echo "${red}[info]${end} Fine，那你自己把yq裝好 :)"
    fi

fi
# Ask if the current cluster is the manin cluster
#read -p "[config] is this cluster the \"main\" cluster? [y/n] " maincluster
#echo "[Debug] maincluster: \"$maincluster\""
kubeconfigpath=~/.kube/config
if [ -f "$kubeconfigpath" ]
then
    echo "${grn}[info]${end} 偵測到 $kubeconfigpath ，已安裝 k8s!"
    read -p "${yel}[config]${end} 這是主叢集嗎? [y/n] " ismaincluster
else
    echo "${red}[info]${end} $kubeconfigpath 不存在"
    read -p "${yel}[config]${end} 這是主叢集嗎? [y/n] " ismaincluster
    read -p "${yel}[config]${end} 幫你裝 Kubernetes ? [y/n] " installk8s
    if [ "$installk8s" == "y" ]
    then
        echo "[info] 開裝k8s"
        echo "${yel}[info]${end} 為了安裝k8s，請輸入目前使用者的密碼(如果有跳提示的話，然後我假設你有sudo權限，然後我不會幫你處理系統升級卡apt-lock)" # 註解好像有點長
        sudo echo "${grn}[info]${end} 我有權限惹!"
        ### start of k8s install recipe
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
        curl -Ol https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64/containerd.io_1.5.10-1_amd64.deb
        curl -Ol https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64/docker-ce_20.10.9~3-0~ubuntu-focal_amd64.deb
        curl -Ol https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64/docker-ce-cli_20.10.9~3-0~ubuntu-focal_amd64.deb
        sudo dpkg -i *.deb
        sudo usermod -aG docker $USER
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo docker version
# 這裡因為 sh 寫檔不能有空格所以要犧牲一下縮排
cat <<EOF | sudo tee /etc/docker/daemon.json
{
"exec-opts": ["native.cgroupdriver=systemd"],
"log-driver": "json-file",
"log-opts": {
    "max-size": "100m"
},
"storage-driver": "overlay2"
}
EOF
        sudo mkdir -p /etc/systemd/system/docker.service.d
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        systemctl status --no-pager docker
        sudo su -c "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -"
        sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
        sudo apt update
        version=1.23.6-00
        echo "${yel} k8s version: $version ${end}"
        apt-cache show kubectl | grep "Version: $version"
        sudo apt install -y kubelet=$version kubectl=$version kubeadm=$version
        sudo apt-mark hold kubelet kubeadm kubectl
        sudo docker pull k8s.gcr.io/kube-apiserver-amd64:v1.23.15
        sudo docker pull k8s.gcr.io/kube-controller-manager-amd64:v1.23.15
        sudo docker pull k8s.gcr.io/kube-scheduler-amd64:v1.23.15
        sudo docker pull k8s.gcr.io/kube-proxy-amd64:v1.23.15
        sudo docker pull k8s.gcr.io/pause:3.6
        sudo docker pull k8s.gcr.io/etcd:3.5.1-0
        sudo docker pull k8s.gcr.io/coredns/coredns:v1.8.6
# 這裡因為 sh 寫檔不能有空格所以要犧牲一下縮排
cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
        sudo swapoff -a
        sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        sudo free -m
        source <(kubectl completion bash)
        echo "source <(kubectl completion bash)" >> ~/.bashrc
        if [ $ismaincluster == "y" ]
        then
            sudo kubeadm init --service-cidr=10.96.0.0/12 --pod-network-cidr=10.244.0.0/16 --v=6
        else
            echo "[info] 非主叢集，init使用--pod-network-cidr=10.245.0.0/16"
            sudo kubeadm init --service-cidr=10.96.0.0/12 --pod-network-cidr=10.245.0.0/16 --v=6
        fi
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        if [ "$ismaincluster" == "y" ]
        then
            echo "[info] 主叢集，直接 apply 一般 flannel yaml"
            kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
        else
            echo "[info] 非主叢集，使用 \"Network\"=\"10.245.0.0/16\" 安裝 flannel"
            curl -sS https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml | sed -e "s/\"Network\": \"10.244.0.0\/16\"/\"Network\": \"10.245.0.0\/16\"/" | kubectl apply -f -
        fi
        kubectl cluster-info
        watch -n 1 kubectl get nodes -o wide
        kubectl taint nodes --all node-role.kubernetes.io/master-
        ### end of k8s install recipe
    else
        echo "${red}[info]${end} 幫你寫好還不用，那你自己裝r"
    fi
fi

# 改k8s叢集名稱和kubeconfigk，這部分要一氣呵成
read -p "${yel}[info]${end} 幫你改叢集名稱? [y/n] " chclustername
cluster1name=kubernetes1
cluster2name=kubernetes2
cluster1user=admin1
cluster2user=admin2
cluster1contextname=c1
cluster2contextname=c2

if [ "$chclustername" == "y" ]
then
    if [ "$ismaincluster" == "y" ]
    then
        echo "${yel}[info]${end} 位於主叢集，將叢集名稱由 \"kubernetes\" 改為 \"$cluster1name\""
        echo "${yel}[info]${end} 給你看一下 kubeadm-config 要改動的部分"
        kubectl get configmaps kubeadm-config -n kube-system -o yaml | sed -e "s/clusterName: kubernetes/clusterName: $cluster1name/" | kubectl diff -f - -n kube-system
        echo "${grn}[info]${end} 好，我幫你把 kubeadm-config 改好惹"
        kubectl get configmaps kubeadm-config -n kube-system -o yaml | sed -e "s/clusterName: kubernetes/clusterName: $cluster1name/" | kubectl apply -f - -n kube-system
        # 這裡要這樣做是因為yq沒有暫存，如果同時讀寫一隻檔案的話那檔案會炸
        yq e ".contexts[0].context.cluster=\"$cluster1name\"" ~/.kube/config > tmp.yaml
        yq e ".clusters[0].name=\"$cluster1name\"" tmp.yaml > ~/.kube/config
        yq e ".contexts[0].context.user=\"$cluster1user\"" ~/.kube/config > tmp.yaml
        yq e ".users[0].name=\"$cluster1user\"" tmp.yaml > ~/.kube/config
        yq e ".contexts[0].name=\"$cluster1contextname\"" ~/.kube/config > tmp.yaml
        yq e ".current-context=\"$cluster1contextname\"" tmp.yaml > ~/.kube/config
        rm tmp.yaml
        echo "${grn}[info]${end} 順便幫你改好kubeconfig惹"
    else
        echo "${yel}[info]${end} 位於非主叢集，將叢集名稱由 \"kubernetes\" 改為 \"$cluster2name\""
        echo "${yel}[info]${end} 給你看一下 kubeadm-config 要改動的部分"
        kubectl get configmaps kubeadm-config -n kube-system -o yaml | sed -e "s/clusterName: kubernetes/clusterName: $cluster2name/" | kubectl diff -f - -n kube-system
        echo "${grn}[info]${end} 好，我幫你把 kubeadm-config 改好惹"
        kubectl get configmaps kubeadm-config -n kube-system -o yaml | sed -e "s/clusterName: kubernetes/clusterName: $cluster2name/" | kubectl apply -f - -n kube-system
        # 這裡要這樣做是因為yq沒有暫存，如果同時讀寫一隻檔案的話那檔案會炸
        yq e ".contexts[0].context.cluster=\"$cluster2name\"" ~/.kube/config > tmp.yaml
        yq e ".clusters[0].name=\"$cluster2name\"" tmp.yaml > ~/.kube/config
        yq e ".contexts[0].context.user=\"$cluster2user\"" ~/.kube/config > tmp.yaml
        yq e ".users[0].name=\"$cluster2user\"" tmp.yaml > ~/.kube/config
        yq e ".contexts[0].name=\"$cluster2contextname\"" ~/.kube/config > tmp.yaml
        yq e ".current-context=\"$cluster2contextname\"" tmp.yaml > ~/.kube/config
        rm tmp.yaml
        echo "${grn}[info]${end} 順便幫你改kubeconfig惹"
    fi
else
    echo "${red}[info]${end} 歐給，幫你寫好還不用，那你自己改"
fi

# 檢查一下次要 kubeconfig 是否存在
# Check if 2nd kubeconfig exist
# 主叢集就拉成 config2 ，非主就拉成 config1
kubeconfig1path=~/.kube/config1
kubeconfig2path=~/.kube/config2

if [ "$ismaincluster" == "y" ]
then
    echo "[info] 位於主叢集，檢查次要kubeconfig是否存在..."
    if [ -f "$kubeconfig2path" ]
    then
        echo "${grn}[info]${end} 偵測到 $kubeconfig2path "
    else
        read -p "${yel}[config]${end} $kubeconfig2path 不存在, 用 scp 從其他台機器拉? [y/n] " scpkubecfg
        if [ "$scpkubecfg" == "y" ]
        then
            read -p "${yel}[config]${end} 輸入像是這樣的使用者和ip \"user 10.20.1.40\" " username ip
            echo "${yel}[config]${end} 執行 \"scp $username@$ip:/home/$username/.kube/config ~/.kube/config2\", 請輸入遠端機器的密碼!"
            scp $username@$ip:/home/$username/.kube/config $kubeconfig2path
        else
            echo "${red}[config]${end} Ok, 你自己把它放在\"~/.kube/config2\""
        fi
    fi
else
    echo "[info] 位於非主叢集，檢查次要kubeconfig是否存在..."
    if [ -f "$kubeconfig1path" ]
    then
        echo "${grn}[config]${end} 偵測到 $kubeconfig1path "
    else
        read -p "${yel}[config]${end} $kubeconfig1path 不存在, 用 scp 從其他台機器拉? [y/n] " scpkubecfg
        if [ "$scpkubecfg" == "y" ]
        then
            read -p "${yel}[config]${end} 輸入像是這樣的使用者和ip \"user 10.20.1.40\" " username ip
            echo "${yel}[config]${end} 執行 \"scp $username@$ip:/home/$username/.kube/config ~/.kube/config1\", 請輸入遠端機器的密碼!"
            scp $username@$ip:/home/$username/.kube/config $kubeconfig1path
        else
            echo "${red}[info]${end} Ok，幫你寫好還不用，你自己把它放在\"~/.kube/config1\""
        fi
    fi
fi

# 新增 2nd 叢集資訊
read -p  "${yel}[config]${end} 幫你新增第二叢集資訊? [y/n] " add2ndcluster
if [ "$add2ndcluster" == "y" ]
then
    if [ "$ismaincluster" == "y" ]
    then
        kubeconfig2read=$kubeconfig2path
    else
        kubeconfig2read=$kubeconfig1path
    fi
    # Cluster
    RemoteClusterCCA=$(yq e ".clusters[0].cluster.certificate-authority-data" $kubeconfig2read)
    RemoteClusterServer=$(yq e ".clusters[0].cluster.server" $kubeconfig2read)
    RemoteClusterName=$(yq e ".clusters[0].name" $kubeconfig2read)
    # Contexts
    RemoteContextCluster=$(yq e ".contexts[0].context.cluster" $kubeconfig2read)
    RemoteContextUser=$(yq e ".contexts[0].context.user" $kubeconfig2read)
    RemoteContextName=$(yq e ".contexts[0].name" $kubeconfig2read)
    # Users
    RemoteUserName=$(yq e ".users[0].name" $kubeconfig2read)
    RemoteUserCCA=$(yq e ".users[0].user.client-certificate-data" $kubeconfig2read)
    RemoteUserCKD=$(yq e ".users[0].user.client-key-data" $kubeconfig2read)
    # Cluster
    echo "${yel}[info]${end} RemoteClusterCCA: $RemoteClusterCCA"
    echo "${yel}[info]${end} RemoteClusterServer: $RemoteClusterServer"
    echo "${yel}[info]${end} RemoteClusterName: $RemoteClusterName"
    # Contexts
    echo "${yel}[info]${end} RemoteContextCluster: $RemoteContextCluster"
    echo "${yel}[info]${end} RemoteContextUser: $RemoteContextUser"
    echo "${yel}[info]${end} RemoteContextName: $RemoteContextName"
    # Users
    echo "${yel}[info]${end} RemoteUserName: $RemoteUserName"
    echo "${yel}[info]${end} RemoteUserCCA: $RemoteUserCCA"
    echo "${yel}[info]${end} RemoteUserCKD: $RemoteUserCKD"
    # 這裡要這樣做是因為yq沒有暫存，如果同時讀寫一隻檔案的話那檔案會炸
    # Cluster
    yq e ".clusters[1].cluster.certificate-authority-data = \"$RemoteClusterCCA\"" ~/.kube/config > tmp.yaml
    yq e ".clusters[1].cluster.server = \"$RemoteClusterServer\"" tmp.yaml > ~/.kube/config
    yq e ".clusters[1].name = \"$RemoteClusterName\"" ~/.kube/config > tmp.yaml
    # Contexts
    yq e ".contexts[1].context.cluster = \"$RemoteContextCluster\"" tmp.yaml > ~/.kube/config
    yq e ".contexts[1].context.user = \"$RemoteContextUser\"" ~/.kube/config > tmp.yaml
    yq e ".contexts[1].name = \"$RemoteContextName\"" tmp.yaml > ~/.kube/config
    # Users
    yq e ".users[1].name = \"$RemoteUserName\"" ~/.kube/config > tmp.yaml
    yq e ".users[1].user.client-certificate-data = \"$RemoteUserCCA\"" tmp.yaml > ~/.kube/config
    yq e ".users[1].user.client-key-data = \"$RemoteUserCKD\"" ~/.kube/config > tmp.yaml
    mv tmp.yaml ~/.kube/config
    export CTX_CLUSTER1=$(kubectl config view -o jsonpath='{.contexts[0].name}')
    export CTX_CLUSTER2=$(kubectl config view -o jsonpath='{.contexts[1].name}')
    echo "export CTX_CLUSTER1=$CTX_CLUSTER1" >> ~/.bashrc
    echo "export CTX_CLUSTER2=$CTX_CLUSTER2" >> ~/.bashrc
else
    echo "${red}[info]${end} 幫你寫好還不用，那你自己慢慢加第二叢集資訊"
fi
