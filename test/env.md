# Install the necessary environments before running tests

- On Ubuntu 16.04
```
$ sudo apt-get install nginx-extras lua5.1 luarocks curl
```

- On Mac OS 10.11.0+
```
$ brew tap denji/nginx
$ brew install nginx-full --with-lua-module
$ brew install lua@5.1
$ brew install curl
```