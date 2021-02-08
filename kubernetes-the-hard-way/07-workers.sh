printf "\n#####\nRun the worker bootstrap script on each worker node\n"

for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  scp -i ssh/kubernetes.id_rsa scripts/worker.sh ubuntu@${external_ip}:~/
  ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip} "~/worker.sh"
done
