ID=`docker container list | grep dnsmasq | cut -d' ' -f1`
docker container logs -f $ID
