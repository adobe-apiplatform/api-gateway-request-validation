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

plan tests => repeat_each() * (blocks() * 9) - 4;

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
     init_worker_by_lua '
        ngx.apiGateway = ngx.apiGateway or {}
        ngx.apiGateway.validation = require "api-gateway.validation.factory"
     ';
    # include "$pwd/conf.d/http.d/*.conf";
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

=== TEST 1: test validator handler can execute on multiple levels
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        set $custom_prop1 "unset";
        set $temp_prop '';

        location /validator_1 {
            set $temp_prop $arg_k;
            content_by_lua '
                ngx.ctx.custom_prop1 = ngx.var.temp_prop
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                ngx.say("OK")
            ';
        }
        location /validator_2 {
            set $temp_prop $arg_key;
            content_by_lua '
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                if ( ngx.ctx.custom_prop1 == ngx.var.temp_prop) then
                    ngx.say("OK")
                    ngx.exit(ngx.OK)
                end
                ngx.status = 401
                ngx.print("you called me too soon")
                ngx.exit(ngx.OK)
            ';
        }

        location /validate-request-test {
            set $custom_prop1 "unset";
            set $request_validator_1 "on; path=/validator_1?k=123; order=1;";
            set $request_validator_2 "on; path=/validator_2?key=123; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid:" .. ngx.var.custom_prop1)
            ';
        }
        location /validate-reverse-order {
            set $custom_prop1 "unset";
            set $request_validator_1  "on; path=/validator_2?key=123; order=1;";
            set $request_validator_2 "on; path=/validator_1?k=123; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid.")
            ';
        }
--- pipelined_requests eval
[
"GET /validate-request-test?debug=true",
"GET /validate-reverse-order?debug=true"
]
--- response_body_like eval
["request is valid:\\d+.*", "^you called me too soon"]
--- response_headers_like eval
[
"X-Debug-Validation-Response-Times: /validator_1\\?k=\\d+, \\d+ ms, status:200, request_validator \\[order:1\\], \\d+ ms, status:200, /validator_2\\?key=\\d+, \\d+ ms, status:200, request_validator \\[order:2\\], \\d+ ms, status:200
Content-Type: text/plain",
"X-Debug-Validation-Response-Times: /validator_2\\?key=\\d+, \\d+ ms, status:401, request_validator \\[order:1\\], \\d+ ms, status:401
Content-Type: text/plain"
]
--- no_error_log
[error]
--- error_code_like eval
[200,401]

=== TEST 2: test OPTIONS request don't get validated
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        set $custom_prop1 "unset";

        location /invalid_validator {
            return 401;
        }
        location /validator_2 {
            return 403;
        }

        location /validate-request-test {
            set $request_validator_1   "on; path=/invalid_validator; order=1;";
            set $request_validator_2 "on; path=/validator_2; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid.")
            ';
        }
--- pipelined_requests eval
[
"GET /validate-request-test?debug=true",
"OPTIONS /validate-request-test?debug=true"]
--- response_body_like eval
[".*401.*",
"request is valid.*"]
--- error_code_like eval
[401,200]
--- no_error_log
[error]



=== TEST 3: test validator can define paths with nginx variables
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        set $custom_prop1 "unset";
        set $temp_prop '';

        location /validator_1 {
            set $temp_prop $arg_k;
            content_by_lua '
                ngx.ctx.custom_prop1 = ngx.var.temp_prop
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                ngx.say("OK")
            ';
        }
        location /validator_2 {
            set $temp_prop $arg_key;
            content_by_lua '
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                if ( ngx.ctx.custom_prop1 == ngx.var.temp_prop) then
                    ngx.say("OK")
                    ngx.exit(ngx.OK)
                end
                ngx.status = 403
                ngx.print("you called me too soon")
                ngx.exit(ngx.OK)
            ';
        }

        location /validate-request-test {
            set $custom_prop1 "unset";
            # THIS VARIABLE IS USED IN THE SECOND VALIDATOR (validator_2 )
            set $can_use_variable "123";
            set $request_validator_1   "on; path=/validator_1?k=123; order=1;";
            set $request_validator_2 "on; path=/validator_2?key=$can_use_variable; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid:" .. ngx.var.custom_prop1)
            ';
        }
        location /validate-reverse-order {
            set $custom_prop1 "unset";
            set $request_validator_1   "on; path=/validator_2?key=123; order=1;";
            set $request_validator_2 "on; path=/validator_1?k=123; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid.")
            ';
        }
--- pipelined_requests eval
[
"GET /validate-request-test?debug=true",
"GET /validate-reverse-order?debug=true"
]
--- response_body_like eval
["request is valid:\\d+.*", "^you called me too soon"]
--- response_headers_like eval
[
"X-Debug-Validation-Response-Times: /validator_1\\?k=\\d+, \\d+ ms, status:200, request_validator \\[order:1\\], \\d+ ms, status:200, /validator_2\\?key=\\d+, \\d+ ms, status:200, request_validator \\[order:2\\], \\d+ ms, status:200
Content-Type: text/plain",
"X-Debug-Validation-Response-Times: /validator_2\\?key=\\d+, \\d+ ms, status:403, request_validator \\[order:1\\], \\d+ ms, status:403
Content-Type: text/plain"
]
--- error_code_like eval
[200,403]
--- no_error_log
[error]

=== TEST 4: test validators configuration with whitespaces
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        set $custom_prop1 "unset";
        set $temp_prop '';

        location /validator_1 {
            set $temp_prop $arg_k;
            content_by_lua '
                ngx.ctx.custom_prop1 = ngx.var.temp_prop
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                ngx.say("OK")
            ';
        }
        location /validator_2 {
            set $temp_prop $arg_key;
            content_by_lua '
                ngx.header["Response-Time"] = ngx.now() - ngx.req.start_time()
                if ( ngx.ctx.custom_prop1 == ngx.var.temp_prop) then
                    ngx.say("OK")
                    ngx.exit(ngx.OK)
                end
                ngx.status = 403
                ngx.print("you called me too soon")
                ngx.exit(ngx.OK)
            ';
        }

        location /validate-request-test {
            set $custom_prop1 "unset";
            # THIS VARIABLE IS USED IN THE SECOND VALIDATOR (validator_2 )
            set $can_use_variable "with_spaces";
            set $request_validator_1   "  on; path=/validator_1?k=with_spaces; order=1;                   ";
            set $request_validator_2 "  on; path=/validator_2?key=$can_use_variable; order=2;   ";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid:" .. ngx.var.custom_prop1)
            ';
        }
        location /validate-reverse-order {
            set $custom_prop1 "unset";
            set $request_validator_2   "on; path=/validator_2?key=123; order=1;";
            set $request_validator_1   "on; path=/validator_1?k=123; order=2;";
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("request is valid.")
            ';
        }
--- pipelined_requests eval
[
"GET /validate-request-test?debug=true",
"GET /validate-reverse-order?debug=true"
]
--- response_body_like eval
["request is valid:with_spaces.*", "^you called me too soon"]
--- response_headers_like eval
[
"X-Debug-Validation-Response-Times: /validator_1\\?k=with_spaces, \\d+ ms, status:200, request_validator \\[order:1\\], \\d+ ms, status:200, /validator_2\\?key=with_spaces, \\d+ ms, status:200, request_validator \\[order:2\\], \\d+ ms, status:200
Content-Type: text/plain",
"X-Debug-Validation-Response-Times: /validator_2\\?key=\\d+, \\d+ ms, status:403, request_validator \\[order:1\\], \\d+ ms, status:403
Content-Type: text/plain"
]
--- error_code_like eval
[200,403]
--- no_error_log
[error]


=== TEST 5: test that if validation fails, the requests terminates at the access phase
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        location /validator_1 {
            return 200;
        }
        location /validator_2 {
            return 401 "Validator 2 says this request is not valid.";
        }

        location /test-invalid-request {
             set $request_validator_1   "on; path=/validator_1; order=1;";
             set $request_validator_2   "on; path=/validator_2; order=2;";
             access_by_lua "ngx.apiGateway.validation.validateRequest()";
             content_by_lua '
                ngx.say("If you see this, validators are failing :(. why ? Pick your answer: http://www.thatwasfunny.com/top-20-programmers-excuses/239")
             ';
        }

--- pipelined_requests eval
[
"GET /test-invalid-request?debug=true"
]
--- response_body_like eval
["^Validator 2 says this request is not valid."]
--- error_code_like eval
[401]
--- response_headers_like eval
[
"Content-Type: text/plain"
]
--- no_error_log
[error]

=== TEST 6: test that validation responses can be customized
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        error_log ../test-logs/validatorHandler_test6_error.log debug;

        set $validator_custom_error_responses '{
            "VALIDATOR_401_ERROR" : {
                "http_status" : 503,
                "error_code"  : 401,
                "message"     : "{\\"error_code\\": \\"-1\\",\\"message\\":\\"custom error message\\", \\"requestID\\":\\"ngx.var.requestID\\", \\"another_ID\\":\\"ngx.var.another_ID\\", \\"var3\\":\\"ngx.var.var3\\", \\"var4\\":\\"ngx.var.var4\\"}",
                "headers"     : {
                    "custom-header-1": "header-1-value",
                    "custom-header-2": "ngx.var.custom_header_2"
                }
            },
            "MISSING_API_KEY": {
                "http_status" : 405,
                "error_code"  : 403000,
                "message"     : "You did not send any key"
            }
        }';

        location /validator_1 {
            return 200;
        }
        location /validator_2 {
            return 401 "Validator 2 says this request is not valid.";
        }

        location /test-invalid-request {
             set $request_validator_1   "on; path=/validator_1; order=1;";
             set $request_validator_2 "on; path=/validator_2; order=2;";
             set $custom_header_2 "this is a lua variable";
             set $requestID "message customization finished";
             set $another_ID "another field";
             set $var3 "var3 value";
             set $var4 "var4 value";

             access_by_lua "ngx.apiGateway.validation.validateRequest()";
             content_by_lua '
                ngx.say("If you see this, validators are failing :(. why ? Pick your answer: http://www.thatwasfunny.com/top-20-programmers-excuses/239")
             ';
        }

        location /test-with-failed-oauth {
            set $validate_oauth_token on;
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("You should not see me")
            ';
        }

        location /test-with-failed-api-key {
            set $validate_api_key on;
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("You should not see me here")
            ';
        }

--- pipelined_requests eval
[
"GET /test-invalid-request?debug=true",
"GET /test-with-failed-oauth",
"GET /test-with-failed-api-key"
]
--- response_body_like eval
[
'^{"error_code": "-1","message":"custom error message", "requestID":"message customization finished", "another_ID":"another field", "var3":"var3 value", "var4":"ngx.var.var4"}+',
'^{"error_code":"403010","message":"Oauth token is missing."}+',
"You did not send any key"
]
--- error_code_like eval
[503,403,405]
--- response_headers_like eval
[
"Content-Type: application/json
custom-header-1: header-1-value
custom-header-2: this is a lua variable",
"Content-Type: application/json",
"Content-Type: application/json"
]
--- no_error_log
[error]


=== TEST 7: test that validation responses when user inputs invalid custom response messages
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        location /validator_1 {
            return 200;
        }
        location /validator_2 {
            return 401 "Validator 2 says this request is not valid.";
        }

        location /test-with-empty-custom-responses {
             set $validator_custom_error_responses '';
             set $request_validator_1   "on; path=/validator_1; order=1;";
             set $request_validator_2 "on; path=/validator_2; order=2;";
             access_by_lua "ngx.apiGateway.validation.validateRequest()";
             content_by_lua '
                ngx.say("If you see this, validators are failing :(. why ? Pick your answer: http://www.thatwasfunny.com/top-20-programmers-excuses/239")
             ';
        }

        location /test-with-invalid-format-custom-responses {
            set $validator_custom_error_responses '{
                "401300" : "I am an invalid formatted custom response object"
            }';
            set $validate_oauth_token on;
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("You should not see me")
            ';
        }


--- pipelined_requests eval
[
"GET /test-with-empty-custom-responses",
"GET /test-with-invalid-format-custom-responses"
]
--- response_body_like eval
[
'^Validator 2 says this request is not valid.+',
'^{"error_code":"403010","message":"Oauth token is missing."}+'
]
--- response_headers_like eval
[
"Content-Type: text/plain",
"Content-Type: application/json"
]
--- error_code_like eval
[401,403]
--- no_error_log
[error]

=== TEST 8: test that validation responses when user inputs invalid custom response messages
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/default_validators.conf;

        location /validator_1 {
            return 200;
        }
        location /validator_2 {
            return 401 "Validator 2 says this request is not valid.";
        }

        location /test-with-empty-custom-responses {
             set $validator_custom_error_responses '';
             set $request_validator_1   "on; path=/validator_1; order=1;";
             set $request_validator_2 "on; path=/validator_2; order=2;";
             access_by_lua "ngx.apiGateway.validation.validateRequest()";
             content_by_lua '
                ngx.say("If you see this, validators are failing :(. why ? Pick your answer: http://www.thatwasfunny.com/top-20-programmers-excuses/239")
             ';
        }

        location /test-with-invalid-format-custom-responses {
            set $validator_custom_error_responses '{
                "401300" : "I am an invalid formatted custom response object"
            }';
            set $validate_oauth_token on;
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua '
                ngx.say("You should not see me")
            ';
        }


--- pipelined_requests eval
[
"GET /test-with-empty-custom-responses",
"GET /test-with-invalid-format-custom-responses"
]
--- response_body_like eval
[
'^Validator 2 says this request is not valid.+',
'^{"error_code":"403010","message":"Oauth token is missing."}+'
]
--- response_headers_like eval
[
"Content-Type: text/plain",
"Content-Type: application/json"
]
--- error_code_like eval
[401,403]
--- no_error_log
[error]


