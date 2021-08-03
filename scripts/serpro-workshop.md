https://gist.github.com/lusoal/8bff1c6c0ed60cfcf1e2ce6eb004d7b9

# Serpro Workshop EKS

Manifestos Básicos

- Provisionar EKS cluster utilizando o eksctl

```sh
eksctl create cluster -f eksworkshop.yaml
```

- Configurar contexto eksctl

```sh
eksctl utils write-kubeconfig --cluster eksworkshop-serpro --region us-east-1
```

- CoreDNS já instalado por padrão
- AWS VPC CNI já instalado por padrao

## Criar identity mapping

- Indentity mapping para visualizar os Pods e recursos no console AWS (RBAC)

```sh
eksctl create iamidentitymapping --cluster eksworkshop-serpro --arn ${rolearn} --group system:masters --username admin
```

## Instalar Add-ons

- Instalar o **metric server** para expor as métricas de scaling

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.4.1/components.yaml
```

## Instalar o Cluster Autoscaler para funcionar o scaling dos Nodes

```sh
eksctl utils associate-iam-oidc-provider \
    --cluster eksworkshop-serpro \
    --approve
```

```sh
cat <<EoF > ./k8s-asg-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EoF

aws iam create-policy   \
  --policy-name k8s-asg-policy \
  --policy-document file://./k8s-asg-policy.json

rm -rf ./k8s-asg-policy.json
```

```sh
eksctl create iamserviceaccount \
    --name cluster-autoscaler \
    --namespace kube-system \
    --cluster eksworkshop-serpro \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/k8s-asg-policy" \
    --approve \
    --override-existing-serviceaccounts
```

- CA with configured SA

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

```sh
kubectl annotate serviceaccount cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/<AmazonEKSClusterAutoscalerRole>
```

```sh
kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
```

## Instalar Load Balancer Controller (Gerenciar Ingress)

- Create IAM policy for service account

```sh
export LBC_VERSION="v2.2.0"

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

- Create service account with above IAM policy

```sh
eksctl create iamserviceaccount \
  --cluster eksworkshop-serpro \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

- Install custom CRD's

```sh
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

kubectl get crd
```

- Deploy Helm Chart

```sh
helm repo add eks https://aws.github.io/eks-charts

helm upgrade -i aws-load-balancer-controller \
    eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=eksworkshop-serpro \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set image.tag="${LBC_VERSION}"

kubectl -n kube-system rollout status deployment aws-load-balancer-controller
```

## Realizar Deploy aplicação

- Criar repositório ECR

```sh
aws ecr create-repository \
    --repository-name my-application \
    --image-scanning-configuration scanOnPush=true \
    --region us-east-1
```

- Buildar imagem

```sh
docker build -t my-application:latest .
```

- Enviar imagem para o ECR

```sh
aws ecr get-login-password --region region | docker login --username AWS --password-stdin aws_account_id.dkr.ecr.region.amazonaws.com
```

```sh
docker tag my-application:latest aws_account_id.dkr.ecr.us-east-1.amazonaws.com/my-application:latest
```

```sh
docker push aws_account_id.dkr.ecr.us-east-1.amazonaws.com/my-application:latest
```

- Alterar manifesto de Deployment com a nova versão da imagem
  - 00-namespace.yaml
  - 01-deployment.yaml
  - 02-configmap.yaml
  - 03-service.yaml
  - 04-hpa.yaml

```sh
kubectl apply -f kubernetes-manifests/
```

- Generate Load to scale with HPA

```sh
kubectl --generator=run-pod/v1 run -i --tty load-generator --image=busybox /bin/sh -nprd
```

```sh
while true; do wget -q -O - http://nginx-deployment; done
```

## Instalar Calico Policy Engine

https://docs.aws.amazon.com/eks/latest/userguide/calico.html

- Install Calico manifests

```sh
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml
```

- Apply the label to namespace

```sh
kubectl label ns prd name=prd
```

- Apply Network Policy to nginx app

```sh
kubectl apply -f kubernetes-manifests/network-policy/06-network-policy.yaml
```

- Test access

```sh
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash
```

- Inside the container run

```sh
curl -IL -XGET nginx-deployment.prd.svc.cluster.local
```

- It will give yout timeout because of Network Policy

- Exit the container and run

```sh
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -nprd -- /bin/bash
```

- Inside the container run

```sh
curl -IL -XGET nginx-deployment.prd.svc.cluster.local
```

- It will give you **200** status code