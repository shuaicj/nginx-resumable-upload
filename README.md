# Nginx Resumable Upload
Nginx Lua module to support resumable upload in nginx. With the help of this module, you can upload a file chunk by chunk, which means one http request uploads one chunk. This is especially useful while uploading big files.



## Contents
- [Get Started](#get-started)
- [Lua APIs](#lua-apis)
- [Upload Request](#upload-request)
    - [Request Method](#request-method)
    - [Request URL](#request-url)
    - [Request Header: Content-Length](#request-header-content-length)
    - [Request Header: Content-Range](#request-header-content-range)
    - [Request Header: X-Checksum-*](#request-header-x-checksum-)
    - [Request Body](#request-body)
- [Upload Response](#upload-response)
    - [Response Status Code](#response-status-code)
    - [Response Header: Content-Range](#response-header-content-range)
    - [Response Header: X-Checksum-*](#response-header-x-checksum-)
    - [Response Body](#response-body)
- [Example Conversation](#example-conversation)



## Get Started
1. Install Nginx with lua support if you haven't done this before.
```
$ brew tap denji/nginx
$ brew install nginx-full --with-lua-module
```
2. Download this module.
```
$ cd your_desired_dir
$ git clone https://github.com/shuaicj/nginx-resumable-upload.git
```
3. Configure your nginx.
```nginx
http {
    lua_package_path 'your_desired_dir/nginx-resumable-upload/lib/?.lua;;';
  
    init_by_lua_block {
        require("shuaicj.upload").init({
            directory = "./upload_files/"
        })  
    }

    server {
        listen        8080;
        server_name   localhost;
        default_type  application/octet-stream;

        client_max_body_size  100m; # set as needed

        location ~ "^/files/([^/]+)$" {
            content_by_lua_block {
                require("shuaicj.upload").upload(ngx.var[1])
            }
        }
    }
}
```
Optionally, you can turn on some kind of checksum validation, e.g.
```nginx
init_by_lua_block {
    require("shuaicj.upload").init({
        directory = "./upload_files/",
        checksum = "md5"
    })
}
```
A possible scenario is that your client app may want to check the size of the file before it start resumable upload. So another `size` api is preferred and your will get the size number in response body with status code `200`. It is safe if the file doesn't exist and of course you got `0` in body but with status code `404`.
```nginx
location ~ "^/files/([^/]+)/size$" {
    content_by_lua_block {
        require("shuaicj.upload").upload(ngx.var[1])
    }
}
```



## Lua APIs
### require("shuaicj.upload").init(config)
Init this lua module. If anything wrong happens, nginx will fail to start. The param `config` is a lua table, and can contains:
- `directory`
    - type: string 
    - description: the directory where to store the uploading files.
    - e.g. `"./uploaded_files/"`
    - required: yes
- `checksum`
    - type: string or table
    - description: checksums to turn on.
    - constraints: only `"crc32"`, `"md5"`, `"sha1"` supported for now.
    - e.g. `"crc32"` or `{"crc32", "sha1"}`
    - required: no
    - default: none is turned on.
- `timeout`
    - type: number
    - description: socket timeout in milliseconds.
    - constraints: must be greater than 0.
    - required: no
    - default: 20000

### require("shuaicj.upload").upload(filename)
The core api for uploading.
- `filename`
    - type: string
    - description: the filename to save.
    - constraints: can only contains alphanumerics `[0-9a-zA-Z]` and three special characters `-` `_` `.` or it will be considered invalid.
    - e.g. `"Test-12_345.txt"`
    - required: yes

### require("shuaicj.upload").size(filename)
Return the file size in byte as http response body. The status code will be `200` if file exists, or else `404`. The param `filename` is the same as above.



## Upload Request

### Request Method
- `POST` : append mode, can only append to the end of file.
- `PUT`  : idempotent write, can replace existing part of file.

### Request URL
A graceful RESTful api for file uploading like `POST|PUT /files/{filename}` is encouraged but not mandatory. In whatever way you like, the filename should be passed into this Lua module as a parameter as mentioned in [Get Started](#get-started).

### Request Header: Content-Length
Required. Implies the size of request body, e.g.
- `Content-Length: 4` : body size 4 bytes.

### Request Header: Content-Range
Required if this is a chunk, not a complete file. Implies the info of this chunk while uploading. It is a standard [HTTP Header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range) designed for download, but here we use it for upload. The format is like `Content-Range: bytes {from}-{to}/{total}`, e.g.
- `Content-Range: bytes 0-3/20` : file size 20 bytes, chunk size 4 bytes, that is [0, 3].
- `Content-Range: bytes 5-9/20` : file size 20 bytes, chunk size 5 bytes, that is [5, 9].
- `Content-Range: bytes 0-19/20` : the chunk is a complete file.

Be careful to set the value of `{from}`. If the file does not exist on server, `{from}` can only be 0. If the file exists and let's say the size is `n`, the value of `{from}` can only be `n` in `POST` mode; while in `PUT` mode, any `0 <= {from} <= n` is valid. See [Request Method](#request-method).

> Note: If you are uploading an empty file (by setting `Content-Length: 0`), the header `Content-Range` will be ignored.

### Request Header: X-Checksum-*
Required if corresponding checksum is turned on while uploading the last chunk. Calculated by client, used for server to check the file integrity. The following kind of checksum is supported:
- `X-Checksum-CRC32` : hex string with fixed length 8, e.g. `abcdef12`.
- `X-Checksum-MD5` : hex string with fixed length 32, e.g. `0123456789abcdef0123456789abcdef`.
- `X-Checksum-SHA1` : hex string with fixed length 40, e.g. `0123456789abcdef0123456789abcdef01234567`.

### Request Body
The bytes of this file chunk.



## Upload Response

### Response Status Code
- `201 Created` : success
- `400 Bad Request` : general client error
- `405 Method Not Allowed` : http method not allowed
- `409 Conflict` : checksum conflict
- `411 Length Required` : header `Content-Length` missing or illegal
- `416 Range Not Satisfiable` : header `Content-Range` missing or illegal
- `500 Internal Server Error` : general server error

### Response Header: Content-Range
Implies the info of file the server already got. See also [Request Header: Content-Range](#request-header-content-range). E.g. assuming the total size of file is 20 bytes, and the server already got 9 bytes, this header should be `Content-Range: bytes 0-8/20`.

### Response Header: X-Checksum-*
Implies the checksum calculated by server. See also [Request Header: X-Checksum-*](#request-header-x-checksum-). This is only present while uploading the last chunk of file and the checksum is turned on, and especially useful while checksums conflict.

### Response Body
Contains error message if something is wrong.



## Example Conversation
Let's upload a file which has 20 bytes content:
```
This world is great.
```
We split it into 3 chunks:

### Chunk 1
```
> POST /files/abc.testfile
> Content-Range: bytes 0-6/20
> Content-Length: 7
>
> This wo

< 201 Created
< Content-Range: bytes 0-6/20
```
### Chunk 2
```
> POST /files/abc.testfile
> Content-Range: bytes 7-14/20
> Content-Length: 8
>
> rld is g

< 201 Created
< Content-Range: bytes 0-14/20
```
### Chunk 3
```
> POST /files/abc.testfile
> Content-Range: bytes 15-19/20
> Content-Length: 5
> X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432
>
> reat.

< 201 Created
< Content-Range: bytes 0-19/20
< X-Checksum-MD5: 8339ed7abf090b1e370edbd93a1f5432
```
