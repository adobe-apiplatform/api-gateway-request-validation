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

plan tests => repeat_each() * (blocks() * 6) - 6;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        -- require "api-gateway.validation"
        require "resty.core"
    ';
    lua_shared_dict test_dict 50m;
    # include "$pwd/conf.d/http.d/*.conf";
    include ../../api-gateway/redis-upstream.conf;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test core validator initialization

--- main_config
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        location /test-base-validator {
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                function TestValidator:sayHello()
                    self:sayIt()
                end
                function TestValidator:sayIt()
                    self:exitFn(201, "Hello from test validator")
                end
                local validator = TestValidator:new()
                validator:sayHello()
            ';
        }
--- request
GET /test-base-validator
--- response_body_like eval
[".*Hello from test validator.*"]
--- error_code: 201
--- no_error_log
[error]

=== TEST 2: test core validator local caching

--- main_config
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        location /post-local-cache {
            limit_except POST {
                deny all;
            }
            set $key $arg_key;
            set $val $arg_val;
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:setKeyInLocalCache(ngx.var.key, ngx.var.val,10,"test_dict")
                if ( res == true ) then
                    validator:exitFn(200, "Saved " .. ngx.var.key .. " in cache")
                else
                    validator:exitFn(200, "Could not save " .. ngx.var.key .. ".")
                end
            ';
        }
        location /local-cache {
            limit_except GET {
                deny all;
            }
            set $key $arg_key;
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:getKeyFromLocalCache(ngx.var.key, "test_dict")
                if ( res ~= nil) then
                    validator:exitFn(200, "Got " .. res .. " from cache")
                else
                    validator:exitFn(200, "Could not read " .. ngx.var.key .. ".")
                end
            ';
        }
--- pipelined_requests eval
["POST /post-local-cache?key=ns1:test-key&val=test-val",
"GET /local-cache?key=ns1:test-key",
"GET /local-cache?key=ns2:INVALID"
]
--- response_body_like eval
[
"^Saved ns1:test-key in cache.*",
"^Got test-val from cache.*",
"^Could not read ns2:INVALID.*"
]
--- no_error_log
[error]

=== TEST 3: test core validator with Redis caching

--- main_config
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        location /post-redis-cache {
            limit_except POST {
                deny all;
            }
            set $key $arg_key;
            set $val $arg_val;
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:setKeyInRedis(ngx.var.key, "test_hash", ((os.time() + 4) * 1000 ) , ngx.var.val)
                if ( res == true ) then
                    validator:exitFn(200, "Saved " .. ngx.var.key .. " in cache")
                else
                    validator:exitFn(200, "Could not save " .. ngx.var.key .. ".")
                end
            ';
        }
        location /redis-cache {
            limit_except GET {
                deny all;
            }
            set $key $arg_key;
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res, err = validator:getKeyFromRedis(ngx.var.key, "test_hash")
                if ( res ~= nil) then
                    validator:exitFn(200, "Got " .. res .. " from cache")
                else
                    validator:exitFn(200, "Could not read " .. ngx.var.key .. ".", err)
                end
            ';
        }
--- pipelined_requests eval
["POST /post-redis-cache?key=ns1:test-key&val=test-val",
"GET /redis-cache?key=ns1:test-key",
"GET /redis-cache?key=ns2:INVALID_REDIS_KEY"
]
--- response_body_like eval
[
"^Saved ns1:test-key in cache.*",
"^Got test-val from cache.*",
"^Could not read ns2:INVALID_REDIS_KEY.*"
]
--- no_error_log
[error]

=== TEST 4: test setContextProperties with object

--- main_config
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        set $prop1 'unset';
        set $prop2 'unset';
        location /test-base-validator {
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local o = {}
                o.prop1 = "prop1-val";
                o.prop2 = "prop2-val";
                o.invalid_prop = "whatever";
                validator:setContextProperties(o)
                ngx.var.prop1 = ngx.ctx.prop1
                ngx.var.prop2 = ngx.ctx.prop2
                validator:exitFn(201, "prop1=" .. ngx.var.prop1 .. ",prop2=" .. ngx.var.prop2)
            ';
        }
--- request
GET /test-base-validator
--- response_body_like eval
[".*prop1=prop1-val,prop2=prop2-val.*"]
--- error_code: 201
--- no_error_log
[error]

=== TEST 5: test setContextProperties with string

--- main_config
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        set $prop1 'unset';
        set $prop2 'unset';
        location /test-base-validator {
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                validator:setContextProperties("{\\"prop1\\":\\"val1\\",\\"prop2\\":\\"val2\\"}")
                ngx.var.prop1 = ngx.ctx.prop1
                ngx.var.prop2 = ngx.ctx.prop2
                validator:exitFn(201, "prop1=" .. ngx.var.prop1 .. ",prop2=" .. ngx.var.prop2)
            ';
        }
--- request
GET /test-base-validator
--- response_body_like eval
[".*prop1=val1,prop2=val2.*"]
--- error_code: 201
--- no_error_log
[error]
