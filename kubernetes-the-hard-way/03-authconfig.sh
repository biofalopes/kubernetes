printf "\n#####\nRetrieve the cluster DNS name\n"

source IDs

#KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
#  --names=kubernetes \
#  --output text --query 'LoadBalancers[0].DNSName')

printf "\n#####\nGenerate a kubeconfig file for each worker node\n"

mkdir -p cfg

for instance in worker-0 worker-1 worker-2; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=tls/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:443 \
    --kubeconfig=cfg/${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=tls/${instance}.pem \
    --client-key=tls/${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=cfg/${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=cfg/${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=cfg/${instance}.kubeconfig
done

printf "\n#####\nGenerate a kubeconfig file for the kube-proxy service\n"
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:443 \
  --kubeconfig=cfg/kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=tls/kube-proxy.pem \
  --client-key=tls/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=cfg/kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=cfg/kube-proxy.kubeconfig

printf "\n#####\nGenerate a kubeconfig file for the kube-controller-manager service\n"

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=tls/kube-controller-manager.pem \
  --client-key=tls/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=cfg/kube-controller-manager.kubeconfig

printf "\n#####\nGenerate a kubeconfig file for the kube-scheduler service\n"

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=tls/kube-scheduler.pem \
  --client-key=tls/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=cfg/kube-scheduler.kubeconfig

printf "\n#####\nGenerate a kubeconfig file for the admin user\n"

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=tls/admin.pem \
  --client-key=tls/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=cfg/admin.kubeconfig

kubectl config use-context default --kubeconfig=cfg/admin.kubeconfig

printf "\n#####\nCopy the appropriate kubelet and kube-proxy kubeconfig files to each worker instance\n"

for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  scp -i ssh/kubernetes.id_rsa \
    cfg/${instance}.kubeconfig cfg/kube-proxy.kubeconfig ubuntu@${external_ip}:~/
done

printf "\n#####\nCopy the appropriate kube-controller-manager and kube-scheduler kubeconfig files to each controller instance\n"

for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  scp -i ssh/kubernetes.id_rsa \
    cfg/admin.kubeconfig cfg/kube-controller-manager.kubeconfig cfg/kube-scheduler.kubeconfig ubuntu@${external_ip}:~/
done
