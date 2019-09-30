#!/bin/bash

echo "log-bin = mysql-bin
server-id = $SERVER_ID">>/etc/mysql/conf.d/docker.conf

docker-entrypoint.sh mysqld