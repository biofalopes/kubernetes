printf "\n###\nCreating VPC\n"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --output text --query 'Vpc.VpcId')
aws ec2 create-tags --resources ${VPC_ID} --tags Key=Name,Value=kubernetes-the-hard-way
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support '{"Value": true}'
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames '{"Value": true}'

printf "\n###\nCreating Subnet\n"
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.0.1.0/24 \
  --output text --query 'Subnet.SubnetId')
aws ec2 create-tags --resources ${SUBNET_ID} --tags Key=Name,Value=kubernetes

printf "\n###\nCreating Internet Gateway\n"
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --output text --query 'InternetGateway.InternetGatewayId')
aws ec2 create-tags --resources ${INTERNET_GATEWAY_ID} --tags Key=Name,Value=kubernetes
aws ec2 attach-internet-gateway --internet-gateway-id ${INTERNET_GATEWAY_ID} --vpc-id ${VPC_ID}

printf "\n###\nCreating Route Table\n"
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --output text --query 'RouteTable.RouteTableId')
aws ec2 create-tags --resources ${ROUTE_TABLE_ID} --tags Key=Name,Value=kubernetes
aws ec2 associate-route-table --route-table-id ${ROUTE_TABLE_ID} --subnet-id ${SUBNET_ID}
aws ec2 create-route --route-table-id ${ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${INTERNET_GATEWAY_ID}

printf "\n###\nCreating Security Group\n"
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes \
  --description "Kubernetes security group" \
  --vpc-id ${VPC_ID} \
  --output text --query 'GroupId')
aws ec2 create-tags --resources ${SECURITY_GROUP_ID} --tags Key=Name,Value=kubernetes
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol all --cidr 10.0.0.0/16
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol all --cidr 10.200.0.0/16
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 6443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol icmp --port -1 --cidr 0.0.0.0/0

printf "\n###\nCreating Load Balancer\n"
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
    --name kubernetes \
    --subnets ${SUBNET_ID} \
    --scheme internet-facing \
    --type network \
    --output text --query 'LoadBalancers[].LoadBalancerArn')
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name kubernetes \
    --protocol TCP \
    --port 6443 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --output text --query 'TargetGroups[].TargetGroupArn')
aws elbv2 register-targets --target-group-arn ${TARGET_GROUP_ARN} --targets Id=10.0.1.1{0,1,2}
aws elbv2 create-listener \
    --load-balancer-arn ${LOAD_BALANCER_ARN} \
    --protocol TCP \
    --port 443 \
    --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}
    
printf "\n###\nObtaining Public Address\n"
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[].DNSName')
  
printf "\n###\nObtaining Image ID\n"
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 \
  --filters \
  'Name=root-device-type,Values=ebs' \
  'Name=architecture,Values=x86_64' \
  'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*' \
  | jq -r '.Images|sort_by(.Name)[-1]|.ImageId')
  
printf "\n###\nCreating key pair\n"
mkdir -p ssh
aws ec2 create-key-pair --key-name kubernetes --output text --query 'KeyMaterial' > ssh/kubernetes.id_rsa
chmod 600 ssh/kubernetes.id_rsa

printf "\n###\nSpawning Controllers\n"
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t3.micro \
    --private-ip-address 10.0.1.1${i} \
    --user-data "name=controller-${i}" \
    --subnet-id ${SUBNET_ID} \
    --block-device-mappings='{"DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 50 }, "NoDevice": "" }' \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute --instance-id ${instance_id} --no-source-dest-check
  aws ec2 create-tags --resources ${instance_id} --tags "Key=Name,Value=controller-${i}"
  printf "controller-${i} created"
  sleep 10
done

printf "\n###\nSpawning Workers\n"
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t3.micro \
    --private-ip-address 10.0.1.2${i} \
    --user-data "name=worker-${i}|pod-cidr=10.200.${i}.0/24" \
    --subnet-id ${SUBNET_ID} \
    --block-device-mappings='{"DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 50 }, "NoDevice": "" }' \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute --instance-id ${instance_id} --no-source-dest-check
  aws ec2 create-tags --resources ${instance_id} --tags "Key=Name,Value=worker-${i}"
  printf "\nworker-${i} created\n"
  sleep 10
done

printf "\n###\nSaving IDs\n"
printf "VPC_ID=${VPC_ID}" >> IDs
printf "SUBNET_ID=${SUBNET_ID}\n" >> IDs
printf "INTERNET_GATEWAY_ID=${INTERNET_GATEWAY_ID}\n" >> IDs
printf "ROUTE_TABLE_ID=${ROUTE_TABLE_ID}\n" >> IDs
printf "SECURITY_GROUP_ID=${SECURITY_GROUP_ID}\n" >> IDs
printf "LOAD_BALANCER_ARN=${LOAD_BALANCER_ARN}\n" >> IDs
printf "TARGET_GROUP_ARN=${TARGET_GROUP_ARN}\n" >> IDs
printf "KUBERNETES_PUBLIC_ADDRESS=${KUBERNETES_PUBLIC_ADDRESS}\n" >> IDs
printf "IMAGE_ID=${IMAGE_ID}\n" >> IDs

printf "\n###\nDone.\n"

