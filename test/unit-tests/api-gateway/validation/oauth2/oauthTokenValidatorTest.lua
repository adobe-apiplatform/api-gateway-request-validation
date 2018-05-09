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

local cjson = require "cjson"
local safeCjson = require "cjson.safe"

local BaseValidatorMock = mock("api-gateway.validation.validator", {
    "new", "exitFn", "getKeyFromLocalCache", "setContextProperties",
    "getKeyFromRedis", "setKeyInLocalCache"
})

local RedisConnectionProviderMock = mock("api-gateway.redis.redisConnectionProvider", {
    "new", "getConnection", "closeConnection"
})

local EXPECTED_RESPONSES = {
    MISSING_TOKEN = { error_code = "403010", message = "Oauth token is missing" },
    INVALID_TOKEN = { error_code = "401013", message = "Oauth token is not valid" },
    TOKEN_MISSMATCH = { error_code = "401014", message = "Token not allowed in the current context" },
    SCOPE_MISMATCH = { error_code = "401015", message = "Scope mismatch" },
    UNKNOWN_ERROR = { error_code = "503010", message = "Could not validate the oauth token" }
}

test('checkResponseFromAuth: should return false for an invalid json', function()
    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local tokenValidity, error = classUnderTest.checkResponseFromAuth("invalid_json", "key")
    assertEquals(tokenValidity, false)
end)

test('checkResponseFromAuth: should return true for a valid json', function()
    local classUnderTest = require('api-gateway.validation.oauth2.oauthTokenValidator'):new()
    local tokenValidity, error = classUnderTest.checkResponseFromAuth("{\"valid\":true,\"expires_at\":$generated_expires_at,\"token\": {\"id\":\"1234\",\"scope\":\"openid email profile\",\"user_id\":\"21961FF44F97F8A10A490D36\",\"expires_in\":\"86400000\",\"client_id\":\"client_id_test_2\",\"type\":\"access_token\"}}", "key")
    assertEquals(tokenValidity, false)
end)

