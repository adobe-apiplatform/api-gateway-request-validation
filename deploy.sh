docker run -v $PWD:/mocka_space \
   -e "LUA_LIBRARIES=src/lua/" -e "PACKAGE=api-gateway-request-validation" -e "ENV=${1}" \
   -e "API_KEY=${API_KEY}" --privileged -i -t adobeapiplatform/mocka:latest /bin/sh /scripts/deploy.sh
