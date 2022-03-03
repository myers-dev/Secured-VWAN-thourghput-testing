#!/bin/bash

apt-get update -y 
#apt-get upgrade -y
apt-get install iperf3 -y

apt-get install python3-pip -y
pip3 install azure.storage.queue

cat<<EOF>client.py
from azure.storage.queue import QueueClient

import socket
import random
import os
from datetime import datetime, timedelta
import time

connection_string = "DefaultEndpointsProtocol=https;EndpointSuffix=core.windows.net;AccountName=storageiperf3;AccountKey=47+mCQ9f8QZSbzLtizkgWKUbhv6t6VU0LRNn81M0RCrnt9adFbbSe+Go6ljakPnN2ec51q29oPOPwLPLWhiAwg=="

queue = QueueClient.from_connection_string(conn_str=connection_string, queue_name="qiperf3")  


message=False

while not message:
    message = queue.receive_message()
    time.sleep(2)

ip=message.content

o=os.popen(f"while true; do iperf3 -c {ip} -P64 -t 300; done").read()

print(o)

EOF

python3 client.py
