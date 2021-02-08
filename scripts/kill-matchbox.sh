ID=`docker container list | grep matchbox | cut -d' ' -f1`
docker container kill $ID
