api-gateway-request-validation
==============================

This module is used to validate a request in the API Gateway

Table of Contents
=================

* [Status](#status)
* [Sample Usage](#sample-usage)
* [Features](#features)
* [Validating requests](#validating-requests)
* [Developer guide](#developer-guide)
* [Resources](#resources)

Status
======

This module is under active development and is NOT YET production ready.

Sample usage
============

```nginx

    http {
        # lua_package_path should point to the location on the disk where the "scripts" folder is located
        lua_package_path "scripts/?.lua;/opt/ADBE/api-gateway/api-gateway-core/scripts/?.lua;;";

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
            access_by_lua_file ../../scripts/request_validator_access_pass.lua;
            content_by_lua "ngx.say('api-key is valid.')";
        }

        # location showing how to protect the endpoint with an OAuth Token
        location /with-oauth-token {
            set $service_id my-service-123;
             # get OAuth token either from header or from the user_token query string
            set $authtoken $http_authorization;
            set_if_empty $authtoken $arg_user_token;
            set_by_lua $authtoken 'return string.gsub(string.gsub(ngx.var.authtoken, "Bearer ", ""), "bearer ", "")';
            set_md5 $authtoken_hash $authtoken;

            set $validate_ims_oauth on;

            # default script used to validate the request
            access_by_lua_file ../../scripts/request_validator_access_pass.lua;
            content_by_lua "ngx.say('ims token is valid.')";
        }

        # proxy to Adobe OAuth provider
        location /imsauth {
            internal;
            set_if_empty $ims_client_id '--change-me--';
            set_if_empty $ims_host 'ims-na1-stg1.adobelogin.com';
            proxy_pass https://$ims_host/ims/validate_token/v1?client_id=$ims_client_id&token=$authtoken;
            proxy_method GET;
            proxy_pass_request_body off;
            proxy_pass_request_headers off;
        }

        # validators can be combined and even executed in a different order
        location /with-api-key-and-ims-token {
            # capture $api_key and $authtoken with $authtoken_hash
            ...
            set $validate_api_key    "on; order=2; ";
            set $validate_ims_oauth  "on; order=1; ";

            # default script used to validate the request
            access_by_lua_file ../../scripts/request_validator_access_pass.lua;
            access_by_lua 'ngx.api-gateway.validateRequest()';

            # then proxy request to a backend service
            proxy_pass $my_proxy_backend_endpoint$request_uri
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

[Back to TOC](#table-of-contents)

Developer guide
===============

## Install the api-gateway first
 Since this module is running inside the `api-gateway`, make sure the api-gateway binary is installed under `/usr/local/sbin`.
 You should have 2 binaries in there: `api-gateway` and `nginx`, the latter being only a symbolik link.

## Update git submodules
```
git submodule update --init --recursive
```

## Developing api-gateway-core library
 This is as straight forward as being able to run the tests.
 In the future, this library will be packed into a tar.gz, versioned, and installed on the operating system alongside the api-gateway.

## Running the tests
The tests are based on the `test-nginx` library.
This library is added a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

Test files are located in `test/perl`.
The other libraries such as `Redis`, `test-nginx` are located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

When tests execute with `make tests`, a few things are happening:
* `Redis` server is compiled and installed in `target/redis-${redis_version}`. The compilation happens only once, not for every tests run, unless `make clear` is executed.
* `Redis` server is started
* `scripts/auth_request_validations.conf` is modified to update the paths and copied in `target/api-gateway` folder.
* `api-gateway` process is started for each test and then closed. The root folder for `api-gateway` is `target/servroot`.
* when tests complete, `Redis` server is closed

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

#### AWS dependency
 Some tests may require AWS IAM Credentials to run correctly. To run these tests you need to execute `make test-aws` like the following command shows:

```
TEST_NGINX_AWS_CLIENT_ID="--change--me" TEST_NGINX_AWS_SECRET="--change-me--" TEST_NGINX_AWS_TOKEN="--change-me--" make test-aws
```

Because these credentials belong to an AWS IAM User ( in this example `apiplatform-web`, you need to SSH into an AWS machine and obtain a set of credentials by running:

```
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/apiplatform-web
```

You can also do the same for a single test:

```
 TEST_NGINX_AWS_CLIENT_ID="--change--me" TEST_NGINX_AWS_SECRET="--change-me--" TEST_NGINX_AWS_TOKEN="--change-me--" \
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 \ prove -I ./test/resources/test-nginx/lib -r ./test/aws-integration/aws/awsKmsSecretReader.t
```

#### Troubleshooting tests

When executing the tests the `test-nginx`library stores the nginx configuration under `target/servroot/`.
It's often useful to consult the logs when a test fails.

For Redis logs, you can consult `target/redis-test.log` file.

Resources
=========

* Testing Nginx : http://search.cpan.org/~agent/Test-Nginx-0.22/lib/Test/Nginx/Socket.pm