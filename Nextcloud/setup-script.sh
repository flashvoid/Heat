#!/bin/bash

host_name=$1
domain_name=$2
ddns_password=$3
ip_address=$4
file_upload_size=$5

bash -x ddns-script.sh $host_name $domain_name $ip_address $ddns_password 

# DNS propagation delay
sleep 1m

# Pull containers
docker pull nginxproxy/nginx-proxy
docker pull nginxproxy/acme-companion
docker pull nextcloud

# Run nginx-proxy
docker run --detach \
 --name nginx-proxy \
 --publish 80:80 \
 --publish 443:443 \
 --volume certs:/etc/nginx/certs \
 --volume vhost:/etc/nginx/vhost.d \
 --volume html:/usr/share/nginx/html \
 --volume /var/run/docker.sock:/tmp/docker.sock:ro \
 nginxproxy/nginx-proxy
 echo client_max_body_size $file_upload_size > /var/lib/docker/volumes/vhost/_data/file_upload
    
# Run acme-companion
docker run --detach \
 --name nginx-proxy-acme \
 --volumes-from nginx-proxy \
 --volume /var/run/docker.sock:/var/run/docker.sock:ro \
 --volume acme:/etc/acme.sh \
 --env "DEFAULT_EMAIL=admin@$domain_name" \
 nginxproxy/acme-companion
    
# Run nextcloud container
docker run --detach \
 --name=nextcloud \
 -e TZ=NZ \
 -p 8080:80 \
 --env "VIRTUAL_HOST=$host_name.$domain_name" \
 --env "LETSENCRYPT_HOST=$host_name.$domain_name"  \
 -v /path/to/appdata:/config \
 -v /path/to/data:/data \
 --restart unless-stopped \
 nextcloud
