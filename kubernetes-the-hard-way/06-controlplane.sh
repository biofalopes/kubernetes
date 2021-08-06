printf "\n#####\nRun the control plane bootstrap script on each controller node\n"

for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  scp -i ssh/kubernetes.id_rsa scripts/controlplane.sh ubuntu@${external_ip}:~/
  ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip} "~/controlplane.sh"
done
