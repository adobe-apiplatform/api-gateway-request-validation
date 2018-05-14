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
local shared = mock("ngx.shared", {"safe_set", "delete"})
local RedisConnectionProviderMock = mock("api-gateway.redis.redisConnectionProvider", {
    "new", "getConnection", "closeConnection"
})

beforeEach(function()
    ngx.config = {
        debug = false
    }

    ngx.__time.doReturn = function()
        return 123
    end

    ngx.shared = {
        cachedOauthTokens = shared
    }
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

