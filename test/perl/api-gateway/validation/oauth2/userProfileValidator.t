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

plan tests => repeat_each() * (blocks() * 8) - 12;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        -- require "resty.core"
    ';
    include "$pwd/conf.d/http.d/*.conf";
    init_worker_by_lua '
        ngx.apiGateway = ngx.apiGateway or {}
        ngx.apiGateway.validation = require "api-gateway.validation.factory"
    ';
    lua_shared_dict cachedkeys 50m; # caches api-keys
    # dict used by OAuth validator to cache valid tokens
    lua_shared_dict cachedOauthTokens 50m;
    # dict used by User Profile validator to cache valid profiles
    lua_shared_dict cachedUserProfiles 50m;
    include ../../api-gateway/redis-upstream.conf;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test oauth_profile is saved correctly in cache and in request variables

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/userProfileValidator_test1_error.log debug;

        location /test-validate-user {
            set $service_id s-123;
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_user_profile on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("user_email=" .. ngx.var.user_email .. ",user_country_code=" .. ngx.var.user_country_code .. ",user_name=" .. ngx.var.user_name)';
        }
        location /local-cache {
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;
            set_md5 $authtoken_hash $authtoken;
            set $key 'cachedoauth:$authtoken_hash';
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local v = BaseValidator:new()
                v["redis_RO_upstream"] = "oauth-redis-ro-upstream"
                v["redis_RW_upstream"] = "oauth-redis-rw-upstream"
                v["redis_pass_env"] = "REDIS_PASS_OAUTH"
                local k = v:getKeyFromLocalCache(ngx.var.key,"cachedUserProfiles")
                v:exitFn(200,"Local: " .. tostring(k))
            ';
        }

        location /redis-cache {
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;
            set_md5 $authtoken_hash $authtoken;
            set $key 'cachedoauth:$authtoken_hash';
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local v = BaseValidator:new()
                v["redis_RO_upstream"] = "oauth-redis-ro-upstream"
                v["redis_RW_upstream"] = "oauth-redis-rw-upstream"
                v["redis_pass_env"] = "REDIS_PASS_OAUTH"
                local k = v:getKeyFromRedis(ngx.var.key,"user_json")
                v:exitFn(200,"Redis: " .. tostring(k))
            ';
        }

        location /validate-user {
            internal;
            return 200 '{"countryCode":"AT","emailVerified":"true","email":"johndoe_ĂÂă@domain.com","userId":"1234","name":"full name","displayName":"display_name—大－女"}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_PROFILE_TEST_1
--- pipelined_requests eval
[
"GET /test-validate-user",
"GET /local-cache",
"GET /redis-cache"
]
--- response_body_like eval
['^user_email=johndoe_ĂÂă\@domain.com,user_country_code=AT,user_name=display_name%E2%80%94%E5%A4%A7%EF%BC%8D%E5%A5%B3.*',
'Local: {"user_name":"display_name—大－女","user_email":"johndoe_ĂÂă@domain.com","user_country_code":"AT"}',
'Redis: {"user_name":"display_name—大－女","user_email":"johndoe_ĂÂă@domain.com","user_country_code":"AT"}']
--- no_error_log
[error]

=== TEST 2: test oauth_profile is saved correctly in cache and in request variables

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/userProfileValidator_test2_error.log debug;

        location /test-validate-user {
            set $service_id s-123;
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_user_profile on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("user_email=" .. ngx.var.user_email .. ",user_country_code=" .. ngx.var.user_country_code .. ",user_name=" .. ngx.var.user_name)';
        }

        location /local-cache {
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local v = BaseValidator:new()
                v["redis_RO_upstream"] = "oauth-redis-ro-upstream"
                v["redis_RW_upstream"] = "oauth-redis-rw-upstream"
                v["redis_pass_env"] = "REDIS_PASS_OAUTH"
                local k = v:getKeyFromLocalCache("cachedoauth:8cd12eadb5032aa2153c8f830d01e0be","cachedUserProfiles")
                v:exitFn(200,k)
            ';
        }

        location /redis-cache {
            content_by_lua '
                local BaseValidator = require "api-gateway.validation.validator"
                local v = BaseValidator:new()
                v["redis_RO_upstream"] = "oauth-redis-ro-upstream"
                v["redis_RW_upstream"] = "oauth-redis-rw-upstream"
                v["redis_pass_env"] = "REDIS_PASS_OAUTH"
                local k = v:getKeyFromRedis("cachedoauth:8cd12eadb5032aa2153c8f830d01e0be","user_json")
                v:exitFn(200,k)
            ';
        }

        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":false,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
        location /validate-user {
            internal;
            return 200 '{"countryCode":"CA","emailVerified":"true","email":"noreply@domain.com","userId":"1234","name":"full name","displayName":"display_name"}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_TWO
--- pipelined_requests eval
[
"GET /test-validate-user",
"GET /local-cache",
"GET /redis-cache"
]
--- response_body_like eval
['^user_email=noreply\@domain.com,user_country_code=CA,user_name=display_name.*',
'{"user_name":"display_name","user_email":"noreply@domain.com","user_country_code":"CA"}',
'{"user_name":"display_name","user_email":"noreply@domain.com","user_country_code":"CA"}']
--- no_error_log
[error]

=== TEST 3: test oauth_profile can add corresponding headers to request

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/userProfileValidator_test3_error.log debug;

        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":false,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
        location /test-validate-user {
            set $service_id s-123;
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_user_profile on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("user_email=" .. ngx.var.user_email .. ",user_country_code=" .. ngx.var.user_country_code .. ",user_name=" .. ngx.var.user_name)';

            add_header X-User-Id $user_email;
            add_header X-User-Country-Code $user_country_code;
            add_header X-User-Name $user_name;
        }

        location /validate-user {
            internal;
            return 200 '{"countryCode":"CA","emailVerified":"true","email":"noreply-ăâ@domain.com","userId":"1234","name":"full name","displayName":"display_name-工－女－长"}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_THREE
--- request
GET /test-validate-user
--- response_body_like eval
"^user_email=noreply-ăâ\@domain.com,user_country_code=CA,user_name=display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF.*"
--- response_headers_like
X-User-Id: noreply-ăâ@domain.com
X-User-Country-Code: CA
X-User-Name: display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF
--- error_code: 200
--- no_error_log
[error]

=== TEST 4: test oauth_profile with a null field

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/userProfileValidator_test4_error.log debug;

        location /test-validate-user {
            set $service_id s-123;
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_user_profile on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("user_email=" .. ngx.var.user_email .. ",user_country_code=" .. ngx.var.user_country_code .. ",user_name=" .. ngx.var.user_name)';

            add_header X-User-Id $user_email;
            add_header X-User-Country-Code $user_country_code;
            add_header X-User-Name $user_name;
        }

        location /validate-user {
            internal;
            return 200 '{"countryCode":null,"emailVerified":"true","email":"noreply-ăâ@domain.com","userId":"1234","name":"full name","displayName":"display_name-工－女－长"}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_FOUR
--- request
GET /test-validate-user
--- response_body_like eval
"^user_email=noreply-ăâ\@domain.com,user_country_code=,user_name=display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF.*"
--- response_headers_like
X-User-Id: noreply-ăâ@domain.com
X-User-Name: display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF
--- error_code: 200
--- no_error_log
[error]

=== TEST 5: test oauth_profile with a null name field

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/userProfileValidator_test5_error.log debug;

        location /test-validate-user {
            set $service_id s-123;
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_user_profile on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua 'ngx.say("user_email=" .. ngx.var.user_email .. ",user_country_code=" .. ngx.var.user_country_code .. ",user_name=" .. ngx.var.user_name)';

            add_header X-User-Id $user_email;
            add_header X-User-Country-Code $user_country_code;
            add_header X-User-Name $user_name;
        }

        location /validate-user {
            internal;
            return 200 '{"countryCode":null,"emailVerified":"true","email":"noreply-ăâ@domain.com","userId":"1234","name":"full name","displayName":"display_name-工－女－长","last_name": null,"first_name": null}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_FIVE
--- request
GET /test-validate-user
--- response_body_like eval
"^user_email=noreply-ăâ\@domain.com,user_country_code=,user_name=display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF.*"
--- response_headers_like
X-User-Id: noreply-ăâ@domain.com
X-User-Name: display_name-%E5%B7%A5%EF%BC%8D%E5%A5%B3%EF%BC%8D%E9%95%BF
--- error_code: 200
--- no_error_log
[error]
