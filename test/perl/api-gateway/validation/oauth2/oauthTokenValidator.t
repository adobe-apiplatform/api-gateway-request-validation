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
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 9) - 6;

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
    include ../../api-gateway/redis-upstream.conf;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test oauth_token is validated correctly

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/oauthTokenValidator_test1_error.log debug;

        location /test-oauth-validation {
            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth token is valid.')";
        }
        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_1
--- request
GET /test-oauth-validation
--- response_body eval
["oauth token is valid.\n"]
--- error_code: 200
--- no_error_log
[error]

=== TEST 2: test oauth_token is saved in the cache

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;
        include ../../api-gateway/api_key_service.conf;

        error_log ../test-logs/oauthTokenValidator_test2_error.log debug;

        location /test-oauth-validation {
            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth token is valid.')";
        }
        location /get-from-cache {
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            content_by_lua '
                local hasher = require "api-gateway.util.hasher"
                local oauthTokenHash = ngx.var.authtoken_hash
                local key = ngx.var.key

                oauthTokenHash = hasher.hash(ngx.var.authtoken)
                key = "cachedoauth:" .. oauthTokenHash

                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                TestValidator["redis_RO_upstream"] = "oauth-redis-ro-upstream"
                TestValidator["redis_RW_upstream"] = "oauth-redis-rw-upstream"
                TestValidator["redis_pass_env"] = "REDIS_PASS_OAUTH"
                local validator = TestValidator:new()
                local res = validator:getKeyFromRedis(key, "token_json")
                if ( res ~= nil) then
                    validator:exitFn(200, res)
                else
                    validator:exitFn(200, "OAuth " .. key .. " not found in local cache")
                end
            ';
        }
        location /test-oauth-token-expiry {
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            content_by_lua '
                local hasher = require "api-gateway.util.hasher"
                local oauthTokenHash = ngx.var.authtoken_hash
                local key = ngx.var.key

                oauthTokenHash = hasher.hash(ngx.var.authtoken)
                key = "cachedoauth:" .. oauthTokenHash

                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:executeTtl(key)
                if ( res ~= nil) then
                    validator:exitFn(200, res)
                end
            ';

            # rewrite /test-oauth-token-expiry(.*)$ /cache/redis_query?$redis_ttl_cmd last;
            # echo $redis_ttl_cmd;
        }
        location /validate-token {
            #internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"client_id_test_2","type":"access_token"}}';
        }
        location /pause {
            content_by_lua '
                ngx.sleep(5)
                ngx.say("OK")
            ';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_2_X_0
--- pipelined_requests eval
["GET /test-oauth-validation",
"GET /get-from-cache",
"GET /validate-token",
"GET /test-oauth-token-expiry",
"GET /pause",
"GET /get-from-cache",
"GET /test-oauth-token-expiry",
]
--- response_body_like eval
[ "oauth token is valid.\n" ,
'.*{"oauth_token_scope":"openid email profile","oauth_token_client_id":"client_id_test_2","oauth_token_user_id":"21961FF44F97F8A10A490D36","oauth_token_expires_at":\\d{13}}.*',
'.*"expires_at":\d+,.*',
'[1-4]', # the cached token expiry time is in seconds, and it can only be between 1s to 4s, but not less. -1 response indicated the key is not cached or it has expired
'OK\n',
'OAuth cachedoauth\:5a6e9de38155078dd80f66330a013c9a3383a87b4879c5ec7ac7b42689330b21 not found in local cache',
'-2' # redis should have expired the oauth token by now
]
--- timeout: 10s
--- no_error_log
[error]

=== TEST 3: test oauth vars are saved in request variables

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;


--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;
        include ../../api-gateway/api_key_service.conf;

        error_log ../test-logs/oauthTokenValidator_test3_error.log debug;

        location /test-oauth-validation {
            #set $oauth_token_scope 'unset';
            #set $oauth_token_client_id 'unset';
            #set $oauth_token_user_id 'unset';

            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth_token_scope=' .. ngx.var.oauth_token_scope .. ',oauth_token_client_id=' .. ngx.var.oauth_token_client_id .. ',oauth_token_user_id=' .. ngx.var.oauth_token_user_id)";
        }
        location /test-oauth-validation-again {
            #set $oauth_token_scope 'unset';
            #set $oauth_token_client_id 'unset';
            #set $oauth_token_user_id 'unset';

            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('AGAIN:oauth_token_scope=' .. ngx.var.oauth_token_scope .. ',oauth_token_client_id=' .. ngx.var.oauth_token_client_id .. ',oauth_token_user_id=' .. ngx.var.oauth_token_user_id)";
        }
        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST3
--- pipelined_requests eval
["GET /test-oauth-validation",
"GET /test-oauth-validation-again"
]
--- response_body_like eval
["oauth_token_scope=openid email profile,oauth_token_client_id=test_Client_ID,oauth_token_user_id=21961FF44F97F8A10A490D36\n",
"AGAIN:oauth_token_scope=openid email profile,oauth_token_client_id=test_Client_ID,oauth_token_user_id=21961FF44F97F8A10A490D36\n",
]
--- no_error_log
[error]

=== TEST 4: test oauth token is saved in redis and in the local cache

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;
        include ../../api-gateway/api_key_service.conf;

        error_log ../test-logs/oauthTokenValidator_test4_error.log debug;

        location /test-oauth-validation {
            #set $oauth_token_scope 'unset';
            #set $oauth_token_client_id 'unset';
            #set $oauth_token_user_id 'unset';

            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth token is valid.')";
        }
        location /test-oauth-validation-again {
            #set $oauth_token_scope 'unset';
            #set $oauth_token_client_id 'unset';
            #set $oauth_token_user_id 'unset';

            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth token is also valid.')";
        }
        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid,AdobeID","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
        location /l2_cache/api_key {
            set $local_key $arg_key;
            content_by_lua_block {
                local localCachedKeys = ngx.shared.cachedOauthTokens;
                if ( nil ~= localCachedKeys ) then
                    local k = localCachedKeys:get(ngx.var.local_key);
                    ngx.say('Local cache:' .. tostring(k) );
                end
            }
        }

        location /query-for-key {
           set $service_id s-123;
           set $authtoken $http_authorization;
           set_if_empty $authtoken $arg_user_token;
           set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;
           set_unescape_uri $query $query_string;
           content_by_lua '
                ngx.log(ngx.DEBUG,"The query value is : "..ngx.var.query)
                local BaseValidator = require "api-gateway.validation.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:getKeyFromRedis(ngx.var.query, "token_json")
                if ( res ~= nil) then
                   ngx.say(tostring(res))
                end
            ';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST4
--- pipelined_requests eval
["GET /test-oauth-validation",
"GET /query-for-key?cachedoauth:46223d289c67faf405c4d20f1c93d518e112d052752eedc58575a04e1e455922",
"GET /test-oauth-validation-again",
"GET /l2_cache/api_key?key=cachedoauth:46223d289c67faf405c4d20f1c93d518e112d052752eedc58575a04e1e455922"
]
--- response_body_like eval
["oauth token is valid.\n",
'.*{"oauth_token_scope":"openid,AdobeID","oauth_token_client_id":"test_Client_ID","oauth_token_user_id":"21961FF44F97F8A10A490D36","oauth_token_expires_at":\\d{13}}.*',
"oauth token is also valid.\n",
'Local cache:{"oauth_token_scope":"openid,AdobeID","oauth_token_client_id":"test_Client_ID","oauth_token_user_id":"21961FF44F97F8A10A490D36","oauth_token_expires_at":\\d{13}}\n'
]
--- no_error_log
[error]

=== TEST 5: test invalid token returns 401

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/api-gateway-cache.conf;
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/oauthTokenValidator_test5_error.log debug;

        location /test-oauth-validation {
            set $service_id s-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('oauth token is valid.')";
        }

        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":false,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }

--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST5
--- request
GET /test-oauth-validation
--- response_body_like: {"error_code":"401013","message":"Oauth token is not valid"}
--- error_code: 401
--- no_error_log
[error]

=== TEST 6: test that validation behaviour can be customized

--- main_config
env REDIS_PASS_API_KEY;
env REDIS_PASS_OAUTH;
env REDIS_PASSWORD;
env REDIS_PASS;

--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/oauthTokenValidator_test6_error.log debug;

        location /validate_custom_oauth_token {
            internal;

            content_by_lua_block {

                ngx.apiGateway.validation.validateOAuthToken({
                    authtoken = ngx.var.custom_token_var,
                    RESPONSES = {
                        MISSING_TOKEN = { error_code = "401110", message = "User token is missing" },
                        INVALID_TOKEN = { error_code = "403113", message = "User token is not valid" },
                        TOKEN_MISSMATCH = { error_code = "401114", message = "User token not allowed in the current context" },
                        SCOPE_MISMATCH = { error_code = "401115", message = "User token scope mismatch" },
                        UNKNOWN_ERROR = { error_code = "503110", message = "Could not validate the user token" }
                    }
                });
            }
        }

        location /test-custom-oauth {
             set $validate_oauth_token "on; path=/validate_custom_oauth_token; order=1;";
             set $custom_token_var $arg_custom_token;
             access_by_lua "ngx.apiGateway.validation.validateRequest()";
             content_by_lua "ngx.say('oauth token is valid.')";
        }

        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":false,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }

--- pipelined_requests eval
[
"GET /test-custom-oauth",
"GET /test-custom-oauth?custom_token=SOME_OAUTH_TOKEN_TEST6"
]
--- response_body_like eval
[
'^{"error_code":"401110","message":"User token is missing"}+',
'^{"error_code":"403113","message":"User token is not valid"}+'
]
--- error_code_like eval
[401,403]
--- no_error_log
[error]

