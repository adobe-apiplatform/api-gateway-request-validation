#!/usr/bin/env bash
 docker run -v $PWD:/mocka_space \
   -e "LUA_LIBRARIES=src/lua/" --privileged -i docker-api-platform-snapshot.dr-uw2.adobeitc.com/apiplatform/utils/mocka:1.0.5.86e6757