-- Copyright (c) 2018 Adobe Systems Incorporated. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.

local safeCjson = require "cjson.safe"
local redisMock = mock("resty.redis", {"new"})
local shared = mock("ngx.shared", {"safe_set", "delete", "get"})
local RedisConnectionProviderMock = mock("api-gateway.redis.redisConnectionProvider", {
    "new", "getConnection", "closeConnection"
})
local sha256Mock = mock("resty.sha256", {"new", "update", "final"})
local hasherMock = mock("api-gateway.util.hasher", {"hash"})

local RESPONSES = {
    INVALID_CLIENT_ID = { error_code = "403201", message = "Client ID not allowed to call this service" },
    MISSING_TOKEN = { error_code = "403010", message = "Oauth token is missing" },
    INVALID_TOKEN = { error_code = "401013", message = "Oauth token is not valid" },
    -- TOKEN_MISSMATCH is reserved for classes overwriting the isTokenValid method
    TOKEN_MISSMATCH = { error_code = "401014", message = "Token not allowed in the current context" },
    SCOPE_MISMATCH = { error_code = "401015", message = "Scope mismatch" },
    UNKNOWN_ERROR = { error_code = "503010", message = "Could not validate the oauth token" }
}

beforeEach(function()

    ngx.header = {}

    ngx.config = {
        debug = false
    }

    ngx.__time.doReturn = function()
        return 123
    end

    ngx.shared = {
        cachedOauthTokens = shared
    }

    ngx.__now.doReturn = function()
        return os.time()
    end

    ngx.req.__start_time.doReturn = function()
        return os.time() - 10
    end

    hasherMock.__hash.doReturn = function(self)
        return "hashedToken"
    end

    ngx.var.oauth_host = "oauth-na1.adobelogin.com"
end)

test('checkResponseFromAuth: should return false for an invalid json', function()
    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local tokenValidity, error = classUnderTest:checkResponseFromAuth("invalid_json", "key")
    assertEquals(tokenValidity, false)
end)

test('checkResponseFromAuth: should return true for a valid json', function()
    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local token = {
        id = "1234", scope = "openid email profile", user_id = "21961FF44F97F8A10A490D36", expires_in = "86400000", client_id = "client_id_test_2", type = "access_token"
    }

    local body = {
        valid = true, expires_at = 3400, token = safeCjson.encode(token)
    }

    local testJson = {
        status = 200,
        body = safeCjson.encode(body)
    }

    local tokenValidity = classUnderTest:checkResponseFromAuth(testJson, "key")
    assertEquals(tokenValidity, true)
end)

test('validateOauthToken: should return 200 for a valid json', function()
    ngx.var.authtoken = "token"

    local tokenInfo = {
        access_token = "token",
        expires_in = 210,
        oauth_token_client_id = 'client_id',
        oauth_token_scope = 'system'
    }

    shared.__get.doReturn = function(self, key)
        return safeCjson.encode(tokenInfo)
    end

    ngx.location.__capture.doReturn = function(self, location, args)
        return {
            status = 200,
            body = safeCjson.encode(tokenInfo)
        }
    end

    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local response_code, response_body = classUnderTest:validateOAuthToken()

    assertEquals(response_code, ngx.HTTP_OK)
end)

test('validateOauthToken: should return 401 for an invalid json', function()
    ngx.var.authtoken = "bad_token"

    local tokenInfo = "invalid_json"

    shared.__get.doReturn = function(self, key)
        return tokenInfo
    end

    ngx.location.__capture.doReturn = function(self, location, args)
        return {
            status = 200,
            body = tokenInfo
        }
    end

    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local responseCode, responseBody = classUnderTest:validateOAuthToken()

    assertEquals(responseCode, RESPONSES.INVALID_TOKEN.error_code)
    assertEquals(RESPONSES.INVALID_TOKEN.message, string.match(responseBody, RESPONSES.INVALID_TOKEN.message))
end)

