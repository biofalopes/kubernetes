source IDs

printf "\n###\nIssuing shutdown to worker nodes...\n"
aws ec2 terminate-instances \
  --instance-ids \
    $(aws ec2 describe-instances --filters \
      "Name=tag:Name,Values=worker-0,worker-1,worker-2" \
      "Name=instance-state-name,Values=running" \
      --output text --query 'Reservations[].Instances[].InstanceId')

printf "\n###\nWaiting for worker nodes to finish terminating...\n"

aws ec2 wait instance-terminated \
  --instance-ids \
    $(aws ec2 describe-instances \
      --filter "Name=tag:Name,Values=worker-0,worker-1,worker-2" \
      --output text --query 'Reservations[].Instances[].InstanceId')

printf "\n###\nIssuing shutdown to master nodes...\n"

aws ec2 terminate-instances \
  --instance-ids \
    $(aws ec2 describe-instances --filter \
      "Name=tag:Name,Values=controller-0,controller-1,controller-2" \
      "Name=instance-state-name,Values=running" \
      --output text --query 'Reservations[].Instances[].InstanceId')

printf "\n###\nWaiting for master nodes to finish terminating...\n"

aws ec2 wait instance-terminated \
  --instance-ids \
    $(aws ec2 describe-instances \
      --filter "Name=tag:Name,Values=controller-0,controller-1,controller-2" \
      --output text --query 'Reservations[].Instances[].InstanceId')

printf "\n###\nDeleting key pair..."

aws ec2 delete-key-pair --key-name kubernetes

printf "\n###\nDeleting Load Balancer...\n"

aws elbv2 delete-load-balancer --load-balancer-arn "${LOAD_BALANCER_ARN}"
aws elbv2 delete-target-group --target-group-arn "${TARGET_GROUP_ARN}"

printf "\n###\nDeleting Security Group...\n"

aws ec2 delete-security-group --group-id "${SECURITY_GROUP_ID}"

printf "\n###\nDeleting Route Table...\n"

ROUTE_TABLE_ASSOCIATION_ID="$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --output text --query 'RouteTables[].Associations[].RouteTableAssociationId')"
aws ec2 disassociate-route-table --association-id "${ROUTE_TABLE_ASSOCIATION_ID}"
aws ec2 delete-route-table --route-table-id "${ROUTE_TABLE_ID}"

printf "\n###\nWaiting a minute for all public address(es) to be unmapped...\n" 

sleep 60

printf "\n###\nDetaching Internet Gateway...\n"

aws ec2 detach-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}" \
  --vpc-id "${VPC_ID}"

printf "\n###\nDeleting Internet Gateway...\n"

aws ec2 delete-internet-gateway --internet-gateway-id "${INTERNET_GATEWAY_ID}"

printf "\n###\nDeleting Subnet...\n"

aws ec2 delete-subnet --subnet-id "${SUBNET_ID}"

printf "\n###\nDeleting VPC...\n"

aws ec2 delete-vpc --vpc-id "${VPC_ID}"

printf "\n###\nDeleting Remaining Files...\n"

rm -rf cfg tls ssh IDs

printf "\n###\nDone.\n\n"
