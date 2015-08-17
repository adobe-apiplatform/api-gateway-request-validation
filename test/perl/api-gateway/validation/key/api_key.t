#/*
# * Copyright (c) 2012 Adobe Systems Incorporated. All rights reserved.
# *
# * Permission is hereby granted, free of charge, to any person obtaining a
# * copy of this software and associated documentation files (the "Software"),
# * to deal in the Software without restriction, including without limitation
# * the rights to use, copy, modify, merge, publish, distribute, sublicense,
# * and/or sell copies of the Software, and to permit persons to whom the
# * Software is furnished to do so, subject to the following conditions:
# *
# * The above copyright notice and this permission notice shall be included in
# * all copies or substantial portions of the Software.
# *
# * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# * DEALINGS IN THE SOFTWARE.
# *
# */
# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4) + 14;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
     init_worker_by_lua '
        ngx.apiGateway = ngx.apiGateway or {}
        ngx.apiGateway.validation = require "api-gateway.validation.factory"
     ';
    lua_shared_dict cachedkeys 50m; # caches api-keys
    upstream api-gateway-redis {
    	server 127.0.0.1:6379;
    }
    upstream api-gateway-redis-replica { # Default config for redis health check test
        server 127.0.0.1:6379;
    }
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test api_key is saved in redis
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        error_log ../test-logs/api_key_test1_error.log debug;

--- more_headers
X-Test: test
--- request
POST /cache/api_key?key=k-123&service_id=s-123
--- response_body eval
["+OK\r\n"]
--- error_code: 200
--- no_error_log
[error]

=== TEST 2: check request without api_key parameter is rejected
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test2_error.log debug;

        location /test-api-key {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('api-key is valid.')";
        }
--- request
GET /test-api-key
--- response_body_like: {"error_code":"403000","message":"Api Key is required"}
--- error_code: 403
--- no_error_log
[error]

=== TEST 3: check request with invalid api_key is rejected
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test3_error.log debug;

        location /test-api-key {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('api-key is valid.')";
        }
--- request
GET /test-api-key?api_key=ab123
--- response_body_like: {"error_code":"403003","message":"Api Key is invalid"}
--- error_code: 403
--- no_error_log
[error]

=== TEST 4: test request with valid api_key
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test4_error.log debug;

        location /test-api-key {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('api-key is valid.')";
        }
--- pipelined_requests eval
["POST /cache/api_key?key=test-key-1234&service_id=s-123",
"GET /test-api-key?api_key=test-key-1234",
"GET /test-api-key?api_key=test-key-1234"]
--- response_body eval
["+OK\r\n",
"api-key is valid.\n",
"api-key is valid.\n"
]
--- no_error_log


=== TEST 5: test that api_key fields are saved in the request variables
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test5_error.log debug;

        location /test-api-key-5 {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "
                ngx.say('service_name=' .. ngx.var.service_name .. ',consumer_org_name=' .. ngx.var.consumer_org_name .. ',app_name=' .. ngx.var.app_name .. ',secret=' .. tostring(ngx.var.key_secret) )
            ";
        }
--- pipelined_requests eval
["POST /cache/api_key?key=test-key-12345&service_id=s-123&service_name=test-service-name&consumer_org_name=test-consumer-name&app_name=test-app-name&secret=my-secret",
"GET /cache/api_key/get?key=test-key-12345&service_id=s-123",
"GET /test-api-key-5?api_key=test-key-12345"]
--- response_body eval
["+OK\r\n",
'{"valid":true}' . "\n",
"service_name=test-service-name,consumer_org_name=test-consumer-name,app_name=test-app-name,secret=my-secret\n"]
--- no_error_log


=== TEST 6: test debug headers
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test6_error.log debug;

        location /test-api-key {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('api-key is valid.')";
        }
--- pipelined_requests eval
["POST /cache/api_key?key=test-key-123&service_id=s-123",
"GET /test-api-key?api_key=test-key-123&debug=true"]
--- response_body eval
["+OK\r\n",
"api-key is valid.\n"]
--- response_headers_like eval
[
"",
"X-Debug-Validation-Response-Times: /validate_api_key, \\d+ ms, status:200, request_validator \\[order:1\\], \\d+ ms, status:200"
]
--- no_error_log
[error]


=== TEST 7: test api-key related field starting with capital H
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        error_log ../test-logs/api_key_test7_error.log debug;

        location /test-api-key {
            set $service_id hH-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            set $validate_api_key on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('api-key is valid.')";
        }
--- pipelined_requests eval
[
"POST /cache/api_key?key=test-key-1234_HHH&service_id=hH-123&app_name=hHHH",
"GET /test-api-key?api_key=test-key-1234_HHH&debug=true"]
--- response_body eval
[
"+OK\r\n",
"api-key is valid.\n"]
--- response_headers_like eval
[
"",
"X-Debug-Validation-Response-Times: /validate_api_key, \\d+ ms, status:200, request_validator \\[order:1\\], \\d+ ms, status:200"
]
--- no_error_log
[error]

