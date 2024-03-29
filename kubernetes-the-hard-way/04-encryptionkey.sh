printf "\n###\nGenerate an encryption key\n"

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

printf "\n###\nCreate the encryption-config.yaml encryption config file\n"

cat > cfg/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

printf "\nCopy the encryption-config.yaml encryption config file to each controller instance\n"

for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances --filters \
    "Name=tag:Name,Values=${instance}" \
    "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  scp -i ssh/kubernetes.id_rsa cfg/encryption-config.yaml ubuntu@${external_ip}:~/
done
