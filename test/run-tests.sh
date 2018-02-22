#!/bin/bash

NAME="abc.testfile"
FILE="./upload_files/$NAME"
UPLOAD_URL="http://localhost:8080/files/$NAME"
SIZE_URL="$UPLOAD_URL/size"
INVALID_UPLOAD_URL="http://localhost:8080/files/ab+c.testfile"

function test
{
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NONE='\033[0m'

    title="$1"
    curl_content="$2"
    file_content="$3"
    shift 3

    #echo "$curl_content"

    status="passed"

    if [ -n "$file_content" ]; then
        if [ ! -f $FILE ] || [ $(cat $FILE | grep "^$file_content$" | wc -l) -eq 0 ]; then
            status="failed"
        fi
    fi
    for v in "$@"; do
        if [ $(echo "$curl_content" | grep "^$v\s*$" | wc -l) -eq 0 ]; then
            status="failed"
        fi
    done

    if [ $status = "passed" ]; then
        echo -e " ${GREEN}Passed: ${NONE}$title"
    else
        echo -e " ${RED}Failed: ${NONE}$title"
    fi
}


# start nginx
nginx -p . -c ./nginx.conf


### tests

rm -f $FILE

test "get size when file not exists" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 404 Not Found" \
     "0"

test "upload first chunk with POST" \
     "$(curl -v -X POST -H 'Content-Range: bytes 0-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "This wo" \
     "< HTTP/1.1 201 Created" \
     "< Content-Range: bytes 0-6/20"

test "get size when file has first chunk" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 200 OK" \
     "7"

test "upload second chunk with POST" \
     "$(curl -v -X POST -H 'Content-Range: bytes 7-14/20' -H 'Content-Length: 8' -d 'rld is g' $UPLOAD_URL 2>&1)" \
     "This world is g" \
     "< HTTP/1.1 201 Created" \
     "< Content-Range: bytes 0-14/20"

test "get size when file has two chunks" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 200 OK" \
     "15"

test "upload last chunk with POST" \
     "$(curl -v -X POST -H 'Content-Range: bytes 15-19/20' -H 'Content-Length: 5' -H 'X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432' -H 'X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a' -H 'X-Checksum-CRC32: 8f6f216a' -d 'reat.' $UPLOAD_URL 2>&1)" \
     "This world is great." \
     "< HTTP/1.1 201 Created" \
     "< Content-Range: bytes 0-19/20" \
     "< X-Checksum-CRC32: 8f6f216a" \
     "< X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432" \
     "< X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a"

test "get size when file has all chunks" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 200 OK" \
     "20"

rm -f $FILE

test "upload an empty file with POST" \
     "$(curl -v -X POST -H 'Content-Length: 0' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 201 Created"

test "get size when file is empty" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 200 OK" \
     "0"

rm -f $FILE

test "upload a complete file with POST" \
     "$(curl -v -X POST -H 'Content-Length: 20' -H 'X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432' -H 'X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a' -H 'X-Checksum-CRC32: 8f6f216a' -d 'This world is great.' $UPLOAD_URL 2>&1)" \
     "This world is great." \
     "< HTTP/1.1 201 Created" \
     "< Content-Range: bytes 0-19/20" \
     "< X-Checksum-CRC32: 8f6f216a" \
     "< X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432" \
     "< X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a"

test "rewrite part of file with PUT" \
     "$(curl -v -X PUT -H 'Content-Range: bytes 5-16/20' -H 'Content-Length: 12' -d 'mmmmmmmmmmmm' $UPLOAD_URL 2>&1)" \
     "This mmmmmmmmmmmmat." \
     "< HTTP/1.1 201 Created" \
     "< Content-Range: bytes 0-19/20"

rm -f $FILE

test "upload with wrong method" \
     "$(curl -v -X GET -H 'Content-Range: bytes 0-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 405 Not Allowed"

test "upload with invalid filename" \
     "$(curl -v -X POST -H 'Content-Range: bytes 0-6/20' -H 'Content-Length: 7' -d 'This wo' $INVALID_UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 400 Bad Request"

test "upload with Content-Length missing" \
     "$(curl -v -X POST -H 'Content-Length: ' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 411 Length Required"

test "upload with Content-Range invalid 1" \
     "$(curl -v -X POST -H 'Content-Range: bytes abcd' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 2" \
     "$(curl -v -X POST -H 'Content-Range: bytes -10-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 3" \
     "$(curl -v -X POST -H 'Content-Range: bytes 8-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 4" \
     "$(curl -v -X POST -H 'Content-Range: bytes 0-6/5' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 5" \
     "$(curl -v -X POST -H 'Content-Range: bytes 0-6/-5' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 6" \
     "$(curl -v -X POST -H 'Content-Range: bytes 0-5/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

curl -X POST -H 'Content-Range: bytes 0-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1

test "upload with Content-Range invalid 7" \
     "$(curl -v -X POST -H 'Content-Range: bytes 10-17/20' -H 'Content-Length: 8' -d 'rld is g' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 8" \
     "$(curl -v -X POST -H 'Content-Range: bytes 1-3/6' -H 'Content-Length: 3' -d 'rld' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

test "upload with Content-Range invalid 9" \
     "$(curl -v -X POST -H 'Content-Range: bytes 9-16/20' -H 'Content-Length: 8' -d 'rld is g' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 416 Requested Range Not Satisfiable"

rm -f $FILE

test "upload without required checksum header" \
     "$(curl -v -X POST -H 'Content-Length: 20' -H 'X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a' -H 'X-Checksum-CRC32: 8f6f216a' -d 'This world is great.' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 400 Bad Request"

test "upload with invalid checksum header" \
     "$(curl -v -X POST -H 'Content-Length: 20' -H 'X-Checksum-MD5: 83mmmm7abf090b1e370edbd93a1f5432' -H 'X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a' -H 'X-Checksum-CRC32: 8f6f216a' -d 'This world is great.' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 400 Bad Request"

curl -X POST -H 'Content-Range: bytes 0-6/20' -H 'Content-Length: 7' -d 'This wo' $UPLOAD_URL 2>&1
curl -X POST -H 'Content-Range: bytes 7-14/20' -H 'Content-Length: 8' -d 'rld is g' $UPLOAD_URL 2>&1

test "upload with conflict checksum" \
     "$(curl -v -X POST -H 'Content-Range: bytes 15-19/20' -H 'Content-Length: 5' -H 'X-Checksum-MD5: ffffed7abf090b1e370edbd93a1f5432' -H 'X-Checksum-SHA1: a7b520214072a6c8eb5924ce8bf16a7072d0970a' -H 'X-Checksum-CRC32: 8f6f216a' -d 'reat.' $UPLOAD_URL 2>&1)" \
     "" \
     "< HTTP/1.1 409 Conflict" \
     "< X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432"

test "file should be empty after checksum conflict" \
     "$(curl -v -X GET $SIZE_URL 2>&1)" \
     "" \
     "< HTTP/1.1 200 OK" \
     "0"

rm -f $FILE


# stop nginx
nginx -s stop
