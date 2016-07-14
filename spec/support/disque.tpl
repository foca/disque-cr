# Disque configuration file example

dir PWD
daemonize yes
pidfile PWD/disque.pid
port PORT
tcp-backlog 511
bind 127.0.0.1
logfile "PWD/disque.log"
loglevel notice
requirepass PASSWORD
