source IDs

for instance in worker-0 worker-1 worker-2; do
  instance_ip=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$instance" --output text --query 'Reservations[].Instances[].PublicIpAddress')
  instance_id=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$instance" --output text --query 'Reservations[].Instances[].InstanceId')
  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"
  echo "${instance_id} ${instance_ip} ${pod_cidr}"

  aws ec2 create-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${pod_cidr}" \
    --instance-id "${instance_id}"
done
