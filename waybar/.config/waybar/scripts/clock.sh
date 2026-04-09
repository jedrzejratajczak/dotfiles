#!/bin/sh
SEP="<span alpha='30%'>|</span>"
TEXT=$(LC_TIME=en_US.UTF-8 date "+%A ${SEP} %d %b %Y ${SEP} %H:%M:%S")
echo "{\"text\": \"${TEXT}\"}"
