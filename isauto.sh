#!/bin/bash
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
end=$'\e[0m'

echo "${grn}[info]${end} Made by vp@22.12.05"
echo "${grn}[info]${end} update@22.12.13 23.03.07 23.03.08 23.03.09"

curshell=$(echo $0 | sed 's/-//g')
echo "${yel}[info]${end} 偵測到使用\"$curshell\"作為shell，相關設定檔會被寫入進\"$HOME/.${curshell}rc\""

# Check if yq is installed
yqpath=/usr/bin/yq
if [ -f "$yqpath" ]
then
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
    echo "${yel}[info]${end} $kubeconfigpath 不存在"
    read -p "${yel}[config]${end} 這是主叢集嗎? [y/n] " ismaincluster
    read -p "${yel}[config]${end} 幫你裝 Kubernetes ? [y/n] " installk8s
    if [ "$installk8s" == "y" ]
    then
        echo "[info] 開裝k8s"
        echo "${yel}[info]${end} 為了安裝k8s，請輸入目前使用者的密碼(我假設你有sudo權限，然後我不會幫你處理系統升級卡apt-lock)" # 註解好像有點長
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
        sudo docker pull k8s.gcr.io/kube-apiserver-amd64:v1.23.17
        sudo docker pull k8s.gcr.io/kube-controller-manager-amd64:v1.23.17
        sudo docker pull k8s.gcr.io/kube-scheduler-amd64:v1.23.17
        sudo docker pull k8s.gcr.io/kube-proxy-amd64:v1.23.17
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
        echo "source <(kubectl completion bash)" >> "$HOME/.${curshell}rc"
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

cp ~/.kube/config ~/.kube/config.bk
echo "${grn}[info]${end} kubeconfig備份於\"$HOME/.kube/config.bk\""

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
            scp $username@$ip:/home/$username/.kube/config.bk $kubeconfig2path
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
            scp $username@$ip:/home/$username/.kube/config.bk $kubeconfig1path
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
    echo "export CTX_CLUSTER1=$CTX_CLUSTER1" >> "$HOME/.${curshell}rc"
    echo "export CTX_CLUSTER2=$CTX_CLUSTER2" >> "$HOME/.${curshell}rc"
else
    echo "${red}[info]${end} 幫你寫好還不用，那你自己慢慢加第二叢集資訊"
fi
### 上面是自動裝好k8s叢集互加

nmappath=/usr/bin/nmap
if [ -f "$nmappath" ]
then
    echo "${grn}[info]${end} 於 $nmappath 偵測到已安裝nmap"
else
    read -p  "${yel}[info]${end} $nmappath 不存在, 幫你裝個? [y/n] " "installnmap"
    if [ "$installnmap" == "y" ]
    then
        echo "${yel}[info]${end} 為了安裝nmap，請輸入目前使用者的密碼(我假設你有sudo權限，然後我不會幫你處理系統升級卡apt-lock)"
        sudo echo "${grn}[info]${end} 我有權限惹!"
        sudo apt install -y nmap
    else
        echo "${red}[info]${end} Fine，那你自己把nmap裝好 :)"
        exit
    fi
fi

# ref: https://stackoverflow.com/questions/13322485/how-to-get-the-primary-ip-address-of-the-local-machine-on-linux-and-os-x
echo "${grn}[info]${end} 偵測到下列網路資訊"
inferenceip=$(hostname -I | cut -d' ' -f1)
echo "IP: \"$inferenceip\""
netmask=$(ifconfig | grep "$inferenceip" | awk -F " " '{print $4}')
echo "遮罩: \"$netmask\""

# ref: https://stackoverflow.com/questions/50413579/bash-convert-netmask-in-cidr-notation
cidr=$(
awk -F. '{
    split($0, octets)
    for (i in octets) {
        mask += 8 - log(2**8 - octets[i])/log(2);
    }
    print "/" mask
}' <<< "$netmask")
echo "遮罩 → CIDR: \"$cidr\""
read -p "${yel}[config]${end} 以上資訊無誤嗎? [y/n] " ifipcorrect

# or and ref: https://unix.stackexchange.com/questions/47584/in-a-bash-script-using-the-conditional-or-in-an-if-statement
if [ "$ifipcorrect" == "n" ] || [ "$ifipcorrect" == "N" ]
then
    echo "${grn}[info]${end} Okay，那等等你幫我手動輸入下，按下\"ENTER\"後顯示網卡相關訊息"
    read pause
    ifconfig
    read -p "${yel}[config]${end} 輸入所使用網卡IP " inferenceip
    read -p "${yel}[config]${end} 輸入所使用網卡遮罩 " netmask
fi

# 優質寫法ref: https://stackoverflow.com/questions/31318068/shell-script-to-remove-a-file-if-it-already-existecho "${grn}[info]${end} 產生所在區網之IP..."
[ -e ip.list ] && rm ip.list
[ -e ipup.list ] && rm ipup.list
[ -e ipdown.list ] && rm ipdown.list
# 記得先裝nmap
#nmap -sL -n "$inferenceip$cidr" | awk '/Nmap scan report/{print $NF}'
nmap -sL -n "$inferenceip$cidr" | awk '/Nmap scan report/{print $NF}' > ip.list
echo "${yel}[info]${end} 區網範圍: $(head -n 1 ip.list) ~ $(tail -n 1 ip.list)"
echo "${grn}[info]${end} 開始掃你家區網..."
# ref: https://stackoverflow.com/questions/1521462/looping-through-the-content-of-a-file-in-bash
# ref: https://stackoverflow.com/questions/60610269/bash-script-for-checking-if-a-host-is-on-the-local-network
while read ip
do
    # echo "$ip"
    if ping -c 1 -W 1 "$ip" 2>&1 >/dev/null;
    then
        echo "$ip ${grn}is up${end}"
        echo "$ip" >> ipup.list
    else
        echo "$ip ${red}is down${end}"
        echo "$ip" >> ipdown.list
fi
done <ip.list
# 去頭去尾
# 去頭ref: https://www.baeldung.com/linux/remove-first-line-text-file
# 去尾ref: https://stackoverflow.com/questions/4881930/remove-the-last-line-from-a-file-in-bash
sed -i '1d' ipdown.list
sed -i '$ d' ipdown.list
# 反向的ipdown.list
# ref: https://stackoverflow.com/questions/742466/how-can-i-reverse-the-order-of-lines-in-a-file
tac ipdown.list > ipdown.list.reverse

if [ "$ismaincluster" == "y" ]
then
    echo "${grn}[info]${end} 位於${yel}主${end}叢集，部署MetalLB之IP將由數字小至大的可用IP優先取得"
    avalipfile2read=ipdown.list
    ipoperator="-1"
else
    echo "${grn}[info]${end} 位於${yel}非主${end}叢集，部署MetalLB之IP將由數字大至小的可用IP優先取得"
    avalipfile2read=ipdown.list.reverse
    ipoperator="+1"
fi

_1sec_pre="0"
_2sec_pre="0"
_3sec_pre="0"
_4sec_pre="0"
ipbreak="0"

while read ip
do
    echo "$ip"
    _1sec=$(echo "$ip" | awk -F "." '{print $1}')
    _2sec=$(echo "$ip" | awk -F "." '{print $2}')
    _3sec=$(echo "$ip" | awk -F "." '{print $3}')
    _4sec=$(echo "$ip" | awk -F "." '{print $4}')
    # echo "${yel}[Debug]${end} _1sec: $_1sec"
    # echo "${yel}[Debug]${end} _2sec: $_2sec"
    # echo "${yel}[Debug]${end} _3sec: $_3sec"
    # echo "${yel}[Debug]${end} _4sec: $_4sec"
    # echo "${yel}[Debug]${end} _1sec_pre: $_1sec_pre"
    # echo "${yel}[Debug]${end} _2sec_pre: $_2sec_pre"
    # echo "${yel}[Debug]${end} _3sec_pre: $_3sec_pre"
    # echo "${yel}[Debug]${end} _4sec_pre: $_4sec_pre"
    if [ "$_1sec" == "$_1sec_pre" ]
    then
        # echo "1st part matched"
        if [ "$_2sec" == "$_2sec_pre" ] && [ "$ipbreak" != "1" ]
        then
            # echo "2nd part matched"
            if [ "$_3sec" == "$_3sec_pre" ] && [ "$ipbreak" != "1" ]
            then
            # echo "3rd part matched"
                if [ "$(($_4sec $ipoperator))" == "$_4sec_pre" ] && [ "$ipbreak" != "1" ]
                then
                    # echo "4th part matched"
                    if [ "$ismaincluster" == "y" ]
                    then
                        gatewayip1="$_1sec_pre.$_2sec_pre.$_3sec_pre.$_4sec_pre"
                        gatewayip2="$_1sec.$_2sec.$_3sec.$_4sec"
                        ipbreak="1"
                    else
                        gatewayip1="$_1sec.$_2sec.$_3sec.$_4sec"
                        gatewayip2="$_1sec_pre.$_2sec_pre.$_3sec_pre.$_4sec_pre"
                        ipbreak="1"
                    fi
                    break
                else
                    # echo "4th part not matched"
                    _4sec_pre=$_4sec
                fi
            else
            # echo "3rd part not matched"
            _3sec_pre=$_3sec
            fi
        else
        # echo "2nd not part matched"
        _2sec_pre=$_2sec
        fi
    else
        # echo "1st not part matched"
        _1sec_pre=$_1sec
    fi
    sleep 0.1
done <$avalipfile2read

if [ -z "$gatewayip1" ]
then
      echo "算你雖，沒找到兩個連續的IP，你自己指定2個要用的IP"
      read -p "${yel}[config]${end} 輸入\"istio gateway ip1\" " gatewayip1
      read -p "${yel}[config]${end} 輸入\"istio gateway ip2\" " gatewayip2
fi

echo "${yel}[info]${end} istio gateway ip1: $gatewayip1"
echo "${yel}[info]${end} istio gateway ip2: $gatewayip2"

# template
cat <<'EOF' >MLB.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      auto-assign: true
      addresses:
      - gatewayip1-gatewayip2
EOF

sed -i "s/gatewayip1/$gatewayip1/g" MLB.yaml
sed -i "s/gatewayip2/$gatewayip2/g" MLB.yaml
echo "${yel}[config]${end} 等會要appy的MetalLB設定"
cat MLB.yaml | yq e

echo "${grn}[info]${end} 安裝並設定MetalLB..."
echo "${grn}[info]${end} 修改kube-proxy configmap，strictARP: ${yel}false${end} → ${yel}true${end}"
echo "${grn}[info]${end} 顯示將作變動部分"
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system
echo "${grn}[info]${end} 修改kube-proxy configmap..."
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
echo "${grn}[info]${end} 創建\"metallb\"之namespace"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
echo "${grn}[info]${end} 設定MLB"
kubectl apply -f MLB.yaml
echo "${grn}[info]${end} 部署MLB"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# istio相關部署
istiover=1.13.1
echo "${yel}[info]${end} istio version: $istiover"
echo "${grn}[info]${end} 下載並解壓istio..."
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$istiover TARGET_ARCH=x86_64 sh -
cd istio-$istiover/
echo "${yel}[config]${end} PATH變動如下↓"
echo "${yel}[config]${end} 原始PATH: ${grn}$PATH${end}"
echo "${yel}[config]${end} PATH變動: ${yel}$PWD/bin:${end}${grn}$PATH${end}"
export PATH=$PWD/bin:$PATH
echo "export PATH=$PWD/bin:$PATH" >> "$HOME/.${curshell}rc"
echo "${grn}[info]${end} 創建\"istio-system\" namespace"
kubectl create --context="$CTX_CLUSTER1" ns istio-system
kubectl create --context="$CTX_CLUSTER2" ns istio-system

if [ "$ismaincluster" == "y" ]
then
    echo "${grn}[info]${end} 位於${yel}主${end}叢集，進行istio相關安裝"
    echo "${grn}[info]${end} 建立 istio 所使用之憑證"
    kubectl create secret generic cacerts -n istio-system --from-file=samples/certs/ca-cert.pem --from-file=samples/certs/ca-key.pem --from-file=samples/certs/root-cert.pem --from-file=samples/certs/cert-chain.pem
    echo "${grn}[info]${end} 設定istio主叢集IstioOperator相關資訊"
    clustername=$cluster1name
    istionetwork="network1"
else
    echo "${grn}[info]${end} 位於${yel}非主${end}叢集，進行istio相關安裝"
    echo "${grn}[info]${end} 建立 istio 所使用之憑證"
    kubectl create secret generic cacerts -n istio-system --from-file=samples/certs/ca-cert.pem --from-file=samples/certs/ca-key.pem --from-file=samples/certs/root-cert.pem --from-file=samples/certs/cert-chain.pem
    echo "${grn}[info]${end} 設定istio相關IstioOperator資訊"
    clustername=$cluster2name
    istionetwork="network2"
fi

echo "${grn}[info]${end} 生成IstioOperator yaml，儲存於\"$(pwd)/IstioOperator.yaml\""
cat <<EOF > IstioOperator.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: clustername2replace
      network: network2replace
EOF

sed -i "s/clusterName: clustername2replace/clusterName: $clustername/" IstioOperator.yaml
sed -i "s/network: network2replace/network: $istionetwork/" IstioOperator.yaml

# 如果是非主叢集的話要加remotePilotAddress
if [ $ismaincluster != "y" ]
then
    # echo "${grn}[info]${end} 位於${yel}非主${end}叢集，請等待主叢集安裝完成後，按下 Enter 以繼續"
    while true
    do
        export DISCOVERY_ADDRESS=$(kubectl \
        --context="${CTX_CLUSTER1}" \
        -n istio-system get svc istio-eastwestgateway \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        echo "\"$DISCOVERY_ADDRESS\""
        if [ -n "$DISCOVERY_ADDRESS" ]
        then
            break
        fi
        sleep 15
    done
    echo "${yel}[info]${end} istio.DISCOVERY_ADDRESS: $DISCOVERY_ADDRESS\""
    if [ -z "$DISCOVERY_ADDRESS" ]
    then
        echo "DISCOVERY_ADDRESS為空值"
    fi
    echo "${grn}[info]${end} 位於${yel}非主${end}叢集，新增\"DISCOVERY_ADDRESS\"變數 -> $DISCOVERY_ADDRESS"
    echo "      remotePilotAddress: ${DISCOVERY_ADDRESS}" >> IstioOperator.yaml
fi
cat IstioOperator.yaml

istioctl install -y -f IstioOperator.yaml

echo "${grn}[info]${end} 安裝 East-West Gateway"
samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster $clustername --network $istionetwork | \
    istioctl install -y -f -

echo "${grn}[info]${end} 公開叢集之apiserver"
kubectl apply -n istio-system -f samples/multicluster/expose-services.yaml

if [ $ismaincluster != "y" ]
then
echo "${grn}[info]${end} 公開主叢集之 api server"
kubectl apply -n istio-system -f samples/multicluster/expose-services.yaml
fi