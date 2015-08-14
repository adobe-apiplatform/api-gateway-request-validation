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
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 8) - 4;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        -- require "resty.core"
    ';
     init_worker_by_lua '
        ngx.apiGateway = ngx.apiGateway or {}
        ngx.apiGateway.validation = require "api-gateway.validation.factory"
     ';
    include "$pwd/conf.d/http.d/*.conf";
    upstream cache_rw_backend {
    	server 127.0.0.1:6379;
    }
    upstream cache_read_only_backend { # Default config for redis health check test
        server 127.0.0.1:6379;
    }
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test basic HMAC SHA1 signature validation
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        location /validate-hmac-sha1 {
            set $hmac_secret 'mO2AIfdUQeQFiGQq';
            set $hmac_source_string $arg_signed_source;
            set $hmac_target_string $arg_signed_target;
            set $hmac_method sha1;

            content_by_lua "ngx.apiGateway.validation.validateHmacSignature()";
        }

--- pipelined_requests eval
["GET /validate-hmac-sha1?signed_source=GET/v1.0/accounts/00000000000000000000000000000000sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&signed_target=q3eNgdryN38VD68CHk6iASM1pok="]
--- error_code_like eval
[200]
--- no_error_log
[error]


=== TEST 2: test HMAC SHA1 validator with request validation
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;

        location /validate-hmac-sha1 {
            set $hmac_secret 'mO2AIfdUQeQFiGQq';
            set $hmac_source_string $arg_signed_source;
            set $hmac_target_string $arg_signed_target;
            set $hmac_method sha1;

            content_by_lua "ngx.apiGateway.validation.validateHmacSignature()";
        }

        location /v1.0/accounts/ {
            set $hmac_secret 'mO2AIfdUQeQFiGQq';
            set $hmac_method sha1;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            #set $hmac_source_string $request_method$uri$api_key;
            # this time lower the the source string
            set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';

            set $hmac_target_string $http_x_api_signature;
            set_if_empty $hmac_target_string $arg_api_signature;

            set $validate_hmac_signature on;
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("signature is valid")';
        }

--- pipelined_requests eval
[
"POST /cache/api_key?key=test-key-1234&service_id=s-123",
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&api_signature=ozRBHws+eNhCjZ3pi43Mn6/G+4k="
]
--- response_body eval
[
"+OK\r\n",
"signature is valid\n"
]
--- error_code_like eval
[200,200]
--- no_error_log
[error]

=== TEST 3: test HMAC SHA1 validator with API KEY validation
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;

        location /v1.0/accounts/ {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            # set $hmac_source_string $request_method$uri$api_key;
            set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';

            set $hmac_target_string $http_x_api_signature;
            set_if_empty $hmac_target_string $arg_api_signature;
            set $hmac_method sha1;

            set $validate_api_key on;
            set $validate_hmac_signature on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("signature is valid")';
        }

--- pipelined_requests eval
[
"POST /cache/api_key?key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&service_id=s-123&secret=mO2AIfdUQeQFiGQq",
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&api_signature=ozRBHws+eNhCjZ3pi43Mn6/G+4k="
]
--- response_body eval
[
"+OK\r\n",
"signature is valid\n"
]
--- error_code_like eval
[200,200]
--- no_error_log
[error]

=== TEST 4: test HMAC SHA1 validator with API KEY validation
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;

        location /v1.0/accounts/ {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            #set $hmac_source_string $request_method$uri$api_key;
            set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';

            set $hmac_target_string $http_x_api_signature;
            set_if_empty $hmac_target_string $arg_api_signature;
            set $hmac_method sha1;

            set $validate_api_key on;
            set $validate_hmac_signature on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("signature is valid")';
        }

--- pipelined_requests eval
[
"POST /cache/api_key?key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&service_id=s-123&secret=mO2AIfdUQeQFiGQq",
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&api_signature=ozRBHws+eNhCjZ3pi43Mn6/G+4k="
]
--- response_body eval
[
"+OK\r\n",
"signature is valid\n"
]
--- error_code_like eval
[200,200]
--- no_error_log
[error]

=== TEST 5: test HMAC SHA1 validator with API KEY validation and custom ERROR MESSAGES
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api_key_service.conf;
        include ../../api-gateway/default_validators.conf;
        # customize error response
        set $validator_custom_error_responses '{
               "MISSING_KEY"   :       { "http_status" : 403, "error_code" : 403000, "message" : "while (1) {}{\\"code\\":1033,\\"description\\":\\"Developer key missing or invalid\\"}" },
               "INVALID_KEY"   :       { "http_status" : 403, "error_code" : 403003, "message" : "while (1) {}{\\"code\\":1033,\\"description\\":\\"Developer key missing or invalid\\"}" },
               "INVALID_SIGNATURE"   : { "http_status" : 403, "error_code" : 403030, "message" : "while (1) {}{\\"code\\":1033,\\"description\\":\\"Call signature missing or invalid\\"}" },
               "INVALID_SIGNATURE"   : { "http_status" : 403, "error_code" : 403033, "message" : "while (1) {}{\\"code\\":1033,\\"description\\":\\"Call signature missing or invalid\\"}" }
        }';

        location /v1.0/accounts/ {
            set $service_id s-123;

            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            #set $hmac_source_string $request_method$uri$api_key;
            set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';

            set $hmac_target_string $http_x_api_signature;
            set_if_empty $hmac_target_string $arg_api_signature;
            set $hmac_method sha1;

            set $validate_api_key on;
            set $validate_hmac_signature on;
            # set $validate_ims_oauth on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("signature is valid")';
        }

--- pipelined_requests eval
[
"POST /cache/api_key?key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&service_id=s-123&secret=mO2AIfdUQeQFiGQq",
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&api_signature=ozRBHws+eNhCjZ3pi43Mn6/G+4k=",
# negative scenario: missing api-key
"GET /v1.0/accounts/00000000000000000000000000000000",
# negative scenario: api_key present but invalid
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=WRONG_KEY_WHICH_DOES_NOT_EXIST",
# negative scenario: api_key is valid but the signature is not
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR&api_signature=WRONG_SIGNATURE",
# negative scenario: api_key is valid , missing signature
"GET /v1.0/accounts/00000000000000000000000000000000?api_key=sZ28nvYnStSUS2dSzedgnwkJtUdLkNdR"
]
--- response_body eval
[
"+OK\r\n",
"signature is valid\n",
'while (1) {}{"code":1033,"description":"Developer key missing or invalid"}' . "\n",
'while (1) {}{"code":1033,"description":"Developer key missing or invalid"}' . "\n",
'while (1) {}{"code":1033,"description":"Call signature missing or invalid"}' . "\n",
'while (1) {}{"code":1033,"description":"Call signature missing or invalid"}' . "\n"
]
--- error_code_like eval
[200,200,403,403,403,403]
--- no_error_log
[error]
