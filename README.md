api-gateway-request-validation
==============================

Lua Module providing a request validation framework in the API Gateway.

### NOTE
This module is written in Lua but you might see Perl as the main language if you look at statistics.
That's because the tests are written in Perl and it's by design that there are more tests than code.
This should be a good indicator of the code and test coverage.

Table of Contents
=================

* [Status](#status)
* [Dependencies](#dependencies)
* [Sample Usage](#sample-usage)
* [Features](#features)
* [Validating requests](#validating-requests)
* [Developer guide](#developer-guide)
* [Resources](#resources)

Status
======

This module is under active development and is NOT YET production ready.

Dependencies
============

This library requires an nginx build with OpenSSL,
the [ngx_lua module](http://wiki.nginx.org/HttpLuaModule), [LuaJIT 2.0](http://luajit.org/luajit.html) and
[api-gateway-hmac](https://github.com/apiplatform/api-gateway-hmac) module.

Sample usage
============

```nginx

    http {
        # lua_package_path should point to the location on the disk where the "scripts" folder is located
        lua_package_path "scripts/?.lua;/src/lua/api-gateway?.lua;;";

        variables_hash_max_size 1024;
        proxy_headers_hash_max_size 1024;

        #
        # allocate memory for caching
        #
        # dict used by api key validator to cache frequently used keys
        lua_shared_dict cachedkeys 50m;
        # dict used by OAuth validator to cache valid tokens
        lua_shared_dict cachedOauthTokens 50m;
        # dic used by OAuth profile validator to cache non PII user profile info
        lua_shared_dict cachedUserProfiles 50m;
        # dict used to store metrics about api calls
        lua_shared_dict stats_counters 50m;
        lua_shared_dict stats_timers 50m;

        #
        # initialize the api-gateway-request-validation object
        #
        init_worker_by_lua '
            ngx.apiGateway = ngx.apiGateway or {}
            ngx.apiGateway.validation = require "api-gateway.validation.factory"
         ';
    }

    server {
        # define validators

        ...
        # location showing how to ensure all requests come with a valid api-key
        # for more examples check api_key.t test file in /test/perl/ folder
        location /with-api-key-check {

            # this is the service identifier. the api-key needs to be associated with it
            set $service_id my-service-123;

            # get the key either from the query params or from the "X-Api-Key" header
            set $api_key $arg_api_key;
            set_if_empty $api_key $http_x_api_key;

            # api-key validator
            set $validate_api_key on;

            # default script used to validate the request
            access_by_lua "ngx.apiGateway.validation.validateRequest()";

            content_by_lua "ngx.say('api-key is valid.')";
        }

        # location showing how to protect the endpoint with an OAuth Token
        location /with-oauth-token {
            set $service_id my-service-123;

             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return ngx.re.gsub(ngx.arg[1], "bearer ", "","ijo") ' $authtoken;

            set $validate_oauth_token on;

            # default script used to validate the request
            access_by_lua "ngx.apiGateway.validation.validateRequest()";
            content_by_lua "ngx.say('OAuth Token is valid.')";
        }

        # proxy to an OAuth provider
        location /validate-token {
            internal;
            set_if_empty $oauth_client_id '--change-me--';
            set_if_empty $oauth_host 'oauth-na1.adobelogin.com';
            proxy_pass https://$oauth_host/oauth/validate_token/v1?client_id=$oauth_client_id&token=$authtoken;
            proxy_method GET;
            proxy_pass_request_body off;
            proxy_pass_request_headers off;
        }

        # validators can be combined and even executed in a different order
        location /with-api-key-and-oauth-token {
            # capture $api_key and $authtoken
            ...
            set $validate_api_key      "on; order=2; ";
            set $validate_oauth_token  "on; order=1; ";

            # default script used to validate the request
            access_by_lua "ngx.apiGateway.validation.validateRequest()";

            # then proxy request to a backend service
            proxy_pass $my_proxy_backend_endpoint$request_uri;
            ...
        }
    }
```
[Back to TOC](#table-of-contents)

Features
========
The API Gateway has a core set of features implemented in this library:

1. It authorises and authenticates applications to consume services, and it also validates application users
2. It enforces Application plans and User plans
3. It sets throttling limits for services
4. It acts as a Web Application Firewall
5. It collects usage and performance data to be used for analytics, billing, performance/SLA management and capacity planning

Besides its core features, the API Gateway provides support for an Extended set of Features, which are not directly implemented into this module:

1. API Analytics
  * Usage
  * Performance
  * Availability
2. API Monetization

Simple code, easy maintenance and performance

[Back to TOC](#table-of-contents)

Validating requests
===================

With the goal to protect APIs, most of the core functionality of the API Gateway is around validating the incoming requests.
Each location can specify what exactly to validate, by enabling one or more validators.

```nginx
    set $validate_api_key     "on;   path=/validate-api-key;   order=1; ";
    set $validate_oauth_token "on;   path=/validate-oauth;     order=2; ";
```

The design principles for request validation are:

* Validators are defined as sub-requests; the `path` property of the validator defines the nginx `location` of the sub-request
* The request is treated as valid when all validators return with `200` HTTP Status.
  * When a validator returns a different status, the nginx execution phase halts and returns immediately.
* Validators usually execute in parallel, unless they're given an order. Multiple validators can have the same order, in which case they execute in parallel.
  * First, validators having `order=1` execute in parallel, then the validators with `order=2` execute and so on.
* Validators can share variables between different execution orders so that a validator with `order=2` can access properties set by a validator with `order=1`
* Properties set by validators can be used later in other request phases such as the `content phase` or the `log phase`
* For CORS, when the request method is `OPTIONS`, validation should be skipped
* Validators execute in the `nginx access phase` of the request, but after other nginx directives such as `deny`, `allow`.

In order to enable request validation for a location you can use the following sample config to get started:

```nginx
#
# default request validation implementation
#
location /validate-request {
    internal;
    content_by_lua 'ngx.apiGateway.validation.defaultValidateRequestImpl()';
}

location /protected-location {

    set $api_key $http_x_api_key;
    set $validate_api_key     "on;   path=/validate-api-key;   order=1; ";

    set $authtoken $http_authorization;
    set $validate_oauth_token "on;   path=/validate-oauth;     order=2; ";

    # validate the request
    access_by_lua "ngx.apiGateway.validation.validateRequest()";

    # ----------------------------------
    #  proxy to the service provider
    # ----------------------------------
    proxy_pass $backend_proxy_pass$request_uri;
}

```

[Back to TOC](#table-of-contents)

Built in validators
===================

### API KEY Validator
Validates the API-KEY by looking in the Redis Cache.
To add a key into the Redis cache you can use the following Redis Command:

```
HMSET cachedkey:$key:$service_id key_secret $key_secret service-id $service_id service-name $service_name realm $realm consumer-org-name $consumer_org_name app-name $app_name
```
* `$key` is the api-key
* `$key_secret` is the secret asociated with the API-KEY. It is recommended to store the encrypted version of the secret in this field and decrypt it when needed.
* `$service_id` is an ID for the service that the API-KEY subscribed to
* `$service_name` is a friendly name for the service_id
* `$realm` could be used to distinguish between a DEV key vs a STAGE key vs a PROD key
* `$consumer_org_name` is the name of the organisation that create the API-KEY. For analytics purposes it's better to group applications created by the same organisation in the same bucket in order to provide a unified view for that organisation.
* `$app_name` is an application identifier which should be unique for an application, even if the API-KEY changes over time


To activate the API-KEY validator simply set `api_key_validator` to on, optionally specifying which internal location to use in order to validate the key.
Think of the internal location as a mean to swap the default implementation with your own.

```nginx
location /protected-with-api-key {
  set $api_key_validator "on;   path=/validate-api-key;  order=1; ";
}
#
# default api-key validator impl
#
location /validate-api-key {
    internal;
    content_by_lua 'ngx.apiGateway.validation.validateApiKey()';
 }
```
To view more examples check `test/perl/api-gateway/validation/key/api_key.t` test file

### HMAC Signature Validator
Validates the HMAC Signature according to a rule you can define in the configuration. This Validator works with HMAC-SHA-1, HMAC-SHA-224, HMAC-SHA-256, HMAC-SHA-384, HMAC-SHA-512.

To enable HMAC validation set `validate_hmac_signature` to on.

```nginx
location /protected-with-hmac {
  set $api_key $http_x_api_key;
  #
  # the HMAC should match to the $hmac_target variable
  #
  set $hmac_target_string $http_x_api_signature;
  #
  # set $hmac_source_string $request_method$uri$api_key
  # this string is used to apply HMAC-SHA* algorithms and if the request is correct, it should match with $hmac_target_string
  set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';
  #
  # $key_secret is populated by api-key-validator
  #
  set $hmac_secret $key_secret;
  set $hmac_method sha1;
  set $validate_hmac_signature "on;   path=/validate_hmac_signature;  order=1; ";
}
location /validate_hmac_signature {
    internal;
    content_by_lua 'ngx.apiGateway.validation.validateHmacSignature()';
}
```

To view more examples on setting up HMAC validator check `test/perl/api-gateway/validation/signing/hmacGenericSignatureValidator.t`.

### OAuth Token Validator
Validates an OAuth Token through a local defined location `/validate-token` that simply proxies the request to the actual OAuth Provider.

Usage:

```nginx

location /protected-with-oauth-token {
    # get OAuth token either from header or from the user_token query string
    set $authtoken $http_authorization;
    set $validate_oauth_token "on;   path=/validate-oauth;  order=1; ";
    ...
    # validate the request
    access_by_lua "ngx.apiGateway.validation.validateRequest()";

    # --------------------------------------------------------------
    #  pass custom headers from oauth token to the backend service
    # --------------------------------------------------------------
    proxy_set_header x-user-id      $oauth_token_user_id;
    proxy_set_header x-client-id    $oauth_token_client_id;
    proxy_set_header x-oauth-scope  $oauth_token_scope;
    # ----------------------------------
    #  proxy to the service provider
    # ----------------------------------
    proxy_pass $backend_proxy_pass$request_uri;
}

#
# default OAuth Token validator impl along with the nginx variables it sets
#
set $oauth_token_scope 'unset';
set $oauth_token_client_id 'unset';
set $oauth_token_user_id 'unset';
location /validate_oauth_token {
    internal;
    content_by_lua 'ngx.apiGateway.validation.validateOAuthToken()';
}

# proxy to an OAuth provider
location /validate-token {
    internal;
    set_if_empty $oauth_client_id '--change-me--';
    set_if_empty $oauth_host 'oauth-na1.adobelogin.com';
    proxy_pass https://$oauth_host/oauth/validate_token/v1?client_id=$oauth_client_id&token=$authtoken;
    proxy_method GET;
    proxy_pass_request_body off;
    proxy_pass_request_headers off;
}
```

To view more examples on setting up OAuth Token validator check `test/perl/api-gateway/validation/oauth2/oauthTokenValidator.t`.

### User profile validator
Validates an existing user profile. Use it to extract user information and pass it on through some headers to the backend service.

Usage:
```nginx
location /protect-with-user-profile-validator {
    # get OAuth token either from header or from the user_token query string
    set $authtoken $http_authorization;
    set $validate_user_profile "on;   path=/validate-user-profile;  order=1; ";

    # --------------------------------------------------------------
    #  pass custom headers form user profile to the backend service
    # --------------------------------------------------------------
    proxy_set_header x-user-display-name    $user_name;
    proxy_set_header x-user-email           $user_email;
    proxy_set_header x-user-country-code    $user_country_code;
    proxy_set_header x-user-region          $user_region;
    # ----------------------------------
    #  proxy to the service provider
    # ----------------------------------
    proxy_pass $backend_proxy_pass$request_uri;
}
#
# default user Profile validator impl along with the nginx variables it sets
#
set $user_email '';
set $user_country_code '';
set $user_region '';
set $user_name '';
location /validate_user_profile {
    internal;
    content_by_lua 'ngx.apiGateway.validation.validateUserProfile()';
}

#proxy to an OAuth identity provider
location /validate-user {
     internal;
     #resolver 8.8.8.8;
     set_if_empty $oauth_client_id '--change-me--';
     set_if_empty $oauth_host 'oauth-na1-stg1.adobelogin.com';
     proxy_pass https://$oauth_host/oauth/profile/v1?client_id=$oauth_client_id&bearer_token=$authtoken;
     proxy_method GET;
     proxy_pass_request_body off;
     proxy_pass_request_headers off;
}
```

To view more examples on setting up OAuth Token validator check `test/perl/api-gateway/validation/oauth2/userProfileValidator.t`.

Developer guide
===============

## Install the api-gateway first
 Since this module is running inside the `api-gateway`, make sure the api-gateway binary is installed under `/usr/local/sbin`.
 You should have 2 binaries in there: `api-gateway` and `nginx`, the latter being only a symbolik link.

## Update git submodules
```
git submodule update --init --recursive
```

## Running the tests
To run unit tests and integration tests, use `./run_tests.sh`

### Unit tests

In order to run the unit tests, the command is `./run_unit_tests.sh`

### Integration tests

#### With docker

```
make test-docker
```
This command spins up 2 containers ( Redis and API Gateway ) and executes the tests in `test/perl`

#### With native binary
```
make test
```

The tests are based on the `test-nginx` library.
This library is added a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

Test files are located in `test/perl`.
The other libraries such as `Redis`, `test-nginx` are located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

When tests execute with `make tests`, a few things are happening:
* `Redis` server is compiled and installed in `target/redis-${redis_version}`. The compilation happens only once, not for every tests run, unless `make clear` is executed.
* `Redis` server is started
* `api-gateway` process is started for each test and then closed. The root folder for `api-gateway` is `target/servroot`
* some test files may output the logs to separate files under `target/test-logs`
* when tests complete successfully, `Redis` server is closed

### Prerequisites
#### MacOS
First make sure you have `Test::Nginx` installed. You can get it from CPAN with something like that:
```
sudo perl -MCPAN -e 'install Test::Nginx'
```
( ref: http://forum.nginx.org/read.php?2,185570,185679 )

Then make sure an `nginx` executable is found in path by symlinking the `api-gateway` executable:
```
ln -s /usr/local/sbin/api-gateway /usr/local/sbin/nginx
export PATH=$PATH:/usr/local/sbin/
```
For openresty you can execute:
```
export PATH=$PATH:/usr/local/openresty/nginx/sbin/
```

#### Other Linux systems:
For the moment, follow the MacOS instructions.

### Executing the tests
 To execute the test issue the following command:
 ```
 make test
 ```
 The build script builds and starts a `Redis` server, shutting it down at the end of the tests.
 The `Redis` server is compiled only the first time, and reused afterwards during the tests execution.
 The default configuration for `Redis` is found under: `test/resources/redis/redis-test.conf`

 If you want to run a single test, the following command helps:
 ```
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/api-gateway/validation/validatorHandler.t
 ```
 This command only executes the test `core_validator.t`.


#### Troubleshooting tests

When executing the tests the `test-nginx`library stores the nginx configuration under `target/servroot/`.
It's often useful to consult the logs when a test fails.
If you run a test but can't seem to find the logs you can edit the configuration for that test specifying an `error_log` location:
```
error_log ../test-logs/validatorHandler_test6_error.log debug;
```

For Redis logs, you can consult `target/redis-test.log` file.

Resources
=========

* Testing Nginx : http://search.cpan.org/~agent/Test-Nginx-0.22/lib/Test/Nginx/Socket.pm
