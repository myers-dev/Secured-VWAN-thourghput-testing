#!/bin/bash

apt-get update -y 
#apt-get upgrade -y
apt-get install iperf3 -y
apt-get install nginx -y
apt-get install python3-pip -y
pip3 install azure.storage.queue

iperf3 -s -D 

cat<<EOF>server.py
from azure.storage.queue import QueueClient

import socket
import random
import os
from datetime import datetime, timedelta

def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('1.1.1.1', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return(IP)


connection_string = "DefaultEndpointsProtocol=https;EndpointSuffix=core.windows.net;AccountName=storageiperf3;AccountKey=47+mCQ9f8QZSbzLtizkgWKUbhv6t6VU0LRNn81M0RCrnt9adFbbSe+Go6ljakPnN2ec51q29oPOPwLPLWhiAwg=="

queue = QueueClient.from_connection_string(conn_str=connection_string, queue_name="qiperf3")

queue.send_message(get_ip(),time_to_live=600)

EOF

python3 server.py