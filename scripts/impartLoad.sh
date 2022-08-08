#!/bin/bash
IP=$1
counter=0
num=$2
while :
do
 ts=`date`
 echo $ts >> "/tmp/loadfile${num}.txt"
 counter=$((counter+1))
 echo " $counter" >> "/tmp/loadfile${num}.txt"
 curl -I $IP -o >> "/tmp/loadfile${num}.txt"
done