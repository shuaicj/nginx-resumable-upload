#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function test
{
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NONE='\033[0m'

    if [ $(echo "$2" | grep "$3" | wc -l) -gt 0 ]; then
        echo -e " ${GREEN}Passed: ${NONE}$1"
    else
        echo -e " ${RED}Failed: ${NONE}$1"
    fi
}

# start nginx
# nginx -p $DIR -c $DIR/nginx.conf

# tests
# TODO

# stop nginx
# nginx -s stop
