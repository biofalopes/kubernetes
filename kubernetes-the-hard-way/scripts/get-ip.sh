instance_ip=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$1" --output text --query 'Reservations[].Instances[].PublicIpAddress')
echo "ssh -i ssh/kubernetes.id_rsa ubuntu@${instance_ip}"

