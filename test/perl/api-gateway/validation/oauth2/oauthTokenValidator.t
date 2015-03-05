# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 7) + 2;

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

    # dict used by OAuth validator to cache valid tokens
    lua_shared_dict cachedOauthTokens 50m;

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

=== TEST 1: test ims_token is validated correctly
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
            content_by_lua "ngx.say('ims token is valid.')";
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
["ims token is valid.\n"]
--- error_code: 200
--- no_error_log
[error]

=== TEST 2: test ims_token is saved in the cache
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
            content_by_lua "ngx.say('ims token is valid.')";
        }
        location /get-from-cache {

            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;
            set_md5 $authtoken_hash $authtoken;

            set $key 'cachedoauth:$authtoken_hash';
            content_by_lua '
                local BaseValidator = require "api-gateway.core.validator"
                local TestValidator = BaseValidator:new()
                local validator = TestValidator:new()
                local res = validator:getKeyFromRedis(ngx.var.key, "token_json")
                if ( res ~= nil) then
                    validator:exitFn(200, res)
                else
                    validator:exitFn(200, "Could not read " .. ngx.var.key .. ".")
                end
            ';
        }
        location /test-oauth-token-expiry {
            # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;
            set_md5 $authtoken_hash $authtoken;
            set $redis_ttl_cmd 'TTL cachedoauth:$authtoken_hash';
            rewrite /test-oauth-token-expiry(.*)$ /cache/redis_query?$redis_ttl_cmd last;
            # echo $redis_ttl_cmd;
        }
        location /validate-token {
            #internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid email profile","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"client_id_test_2","type":"access_token"}}';
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST_2_X_0
--- pipelined_requests eval
["GET /test-oauth-validation",
"GET /get-from-cache",
"GET /validate-token",
"GET /test-oauth-token-expiry"
]
--- response_body_like eval
[ "ims token is valid.\n" ,
'.*{"oauth_token_client_id":"client_id_test_2","oauth_token_scope":"openid email profile","oauth_token_user_id":"21961FF44F97F8A10A490D36"}.*',
'.*"expires_at":\d+,.*',
'^:[1-4]\r\n$' # the cached token expiry time is in seconds, and it can only be between 1s to 4s, but not less. -1 response indicated the key is not cached or it has expired
]
--- no_error_log
[error]

=== TEST 3: test oauth vars are saved in request variables
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

=== TEST 4: test IMS token is saved in redis and in the local cache
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
            content_by_lua "ngx.say('ims token is valid.')";
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
            content_by_lua "ngx.say('ims token is also valid.')";
        }
        location /validate-token {
            internal;
            set_by_lua $generated_expires_at 'return ((os.time() + 4) * 1000 )';
            return 200 '{"valid":true,"expires_at":$generated_expires_at,"token":{"id":"1234","scope":"openid,AdobeID","user_id":"21961FF44F97F8A10A490D36","expires_in":"86400000","client_id":"test_Client_ID","type":"access_token"}}';
        }
        location /l2_cache/api_key {
            set $local_key $arg_key;
            content_by_lua "
                local localCachedKeys = ngx.shared.cachedOauthTokens;
                if ( nil ~= localCachedKeys ) then
                    local k = localCachedKeys:get(ngx.var.local_key);
                    ngx.say('Local cache:' .. tostring(k) );
                    -- ngx.say('Local cache:' .. ngx.var.local_key);
                end
            ";
        }
--- more_headers
Authorization: Bearer SOME_OAUTH_TOKEN_TEST4
--- pipelined_requests eval
["GET /test-oauth-validation",
"GET /cache/redis_query?HGET%20cachedoauth:1eb30b79089ce83d1b18a89501b41998%20token_json",
"GET /test-oauth-validation-again",
"GET /l2_cache/api_key?key=cachedoauth:1eb30b79089ce83d1b18a89501b41998"
]
--- response_body_like eval
["ims token is valid.\n",
'.*{"oauth_token_client_id":"test_Client_ID","oauth_token_scope":"openid,AdobeID","oauth_token_user_id":"21961FF44F97F8A10A490D36"}.*',
"ims token is also valid.\n",
'Local cache:{"oauth_token_client_id":"test_Client_ID","oauth_token_scope":"openid,AdobeID","oauth_token_user_id":"21961FF44F97F8A10A490D36"}\n'
]
--- no_error_log
[error]

=== TEST 5: test invalid token returns 401
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
            content_by_lua "ngx.say('ims token is valid.')";
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

