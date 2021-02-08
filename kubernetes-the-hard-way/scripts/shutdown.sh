printf "\n#####\nShutdown Instances\n"

for instance in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip} "sudo shutdown -h now"
done
