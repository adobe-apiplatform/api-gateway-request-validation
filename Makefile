# NOTE: Every line in a recipe must begin with a tab character.
BUILD_DIR ?= target
REDIS_VERSION ?= 2.8.6

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install
TEST_NGINX_AWS_CLIENT_ID ?= ''
TEST_NGINX_AWS_SECRET ?= ''

.PHONY: all clean test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/validation/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/validation/key/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/redis/
	$(INSTALL) src/lua/api-gateway/validation/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/validation/
	$(INSTALL) src/lua/api-gateway/validation/key/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/validation/key/
	$(INSTALL) src/lua/api-gateway/redis/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/redis/

test: redis
	echo "Starting redis server on default port"
	$(BUILD_DIR)/redis-$(REDIS_VERSION)/src/redis-server test/resources/redis/redis-test.conf
	echo "updating git submodules ..."
	if [ ! -d "test/resources/test-nginx/lib" ]; then	git submodule update --init --recursive; fi
	echo "running tests ..."
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	cp -r test/resources/api-gateway $(BUILD_DIR)

	TEST_NGINX_AWS_CLIENT_ID="${TEST_NGINX_AWS_CLIENT_ID}" TEST_NGINX_AWS_SECRET="${TEST_NGINX_AWS_SECRET}" PATH=/usr/local/sbin:$$PATH TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl
	cat $(BUILD_DIR)/redis-test.pid | xargs kill

redis: all
	mkdir -p $(BUILD_DIR)
	tar -xf test/resources/redis/redis-$(REDIS_VERSION).tar.gz -C $(BUILD_DIR)/
	cd $(BUILD_DIR)/redis-$(REDIS_VERSION) && make

package:
	git archive --format=tar --prefix=api-gateway-request-validation-1.0/ -o api-gateway-request-validation-1.0.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)