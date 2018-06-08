#!/usr/bin/env bash
docker run -v $PWD:/mocka_space \
    -e "LUA_LIBRARIES=src/lua/" --privileged -i adobeapiplatform/luamock:latest