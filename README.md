# Nginx Resumable Upload
Nginx Lua module to support resumable upload in nginx. With the help of this module, you can upload a file chunk by chunk, which means one http request uploads one chunk. This is especially useful while uploading big files.



## Contents
- [Get Started](#get-started)
- [Upload Request](#upload-request)
    - [Request Method](#request-method)
    - [Request URL](#request-url)
    - [Request Header: Content-Range](#request-header-content-range)
    - [Request Header: Content-Length](#request-header-content-length)
    - [Request Header: X-Checksum-*](#request-header-x-checksum-)
    - [Request Body](#request-body)
- [Upload Response](#upload-response)
    - [Response Status Code](#response-status-code)
    - [Response Header: Content-Range](#response-header-content-range)
    - [Response Header: X-Checksum-*](#response-header-x-checksum-)
    - [Response Body](#response-body)
- [Example Conversation](#example-conversation)



## Get Started



## Upload Request

### Request Method
Generally `POST` or `PUT` is encouraged, although it is configurable.

### Request URL
A graceful RESTful api for file uploading like `POST /files/{filename}` is encouraged but not mandatory. In whatever way you like, the filename should be passed into this Lua module as a parameter as mentioned in [Get Started](#get-started).
> Note: Make sure your filename contains only alphanumerics `[0-9a-zA-Z]` and three special characters `.` `-` `_` or it will be considered invalid.

### Request Header: Content-Range
Required. Implies the info of this chunk while uploading. It is a standard [HTTP Header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range) designed for download, but here we use it for upload. The format is like `Content-Range: bytes {from}-{to}/{total}`, e.g.
- `Content-Range: bytes 0-3/20` : file size 20 bytes, chunk size 4 bytes, that is [0, 3].
- `Content-Range: bytes 5-9/20` : file size 20 bytes, chunk size 5 bytes, that is [5, 9].
- `Content-Range: bytes 0-19/20` : the chunk is a complete file.
> Note: Be careful to set the value of `{from}`, because this Lua module supports `create/recreate/append` only. It means, if the file does not exist on server, `{from}` can only be 0; if the file exists and let's say the size is `n`, the value of `{from}` can only be 0 or `n`.

### Request Header: Content-Length
Required. Implies the size of this chunk, e.g.
- `Content-Length: 4` : chunk size 4 bytes.

### Request Header: X-Checksum-*
Optional. The checksum calculated by client, used for server to check the file integrity. If you turned on the configuration of some kind of checksum, you should set the corresponding header while uploading the last chunk. The following kind of checksum is supported:
- `X-Checksum-CRC32` : hex string with max length 8, e.g. `abcdef12`.
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
- `411 Length Required` : header `Content-Length` missing
- `416 Range Not Satisfiable` : header `Content-Range` missing or illegal
- `500 Internal Server Error` : general server error

### Response Header: Content-Range
Implies the info of file the server already got. See also [Request Header: Content-Range](#request-header-content-range). E.g. assuming the total size of file is 20 bytes, and the server already got 9 bytes, this header should be `Content-Range: bytes 0-8/20`.

### Response Header: X-Checksum-*
Implies the checksum calculated by server. See also [Request Header: X-Checksum-*](#request-header-x-checksum-). This is only present while uploading the last chunk of file, and especially useful while checksums conflict.

### Response Body
Contains error message if something is wrong.



## Example Conversation
Let's upload a file which has 20 bytes content:
```
This world is great!
```
We split it into 3 chunks:
### Chunk 1
```
This wo
```
### Chunk 2
```
rld is g
```
### Chunk 3
```
reat!
```
