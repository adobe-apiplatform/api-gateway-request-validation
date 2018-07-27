---
--- Created by purcarea.
--- DateTime: 30/03/2018
---

local cjson = require "cjson"

local BaseValidatorMock, RedisConnectionProviderMock

local EXPECTED_RESPONSES = {
    MISSING_KEY = { error_code = "403000", message = '{"message":"Api KEY is missing","error_code":"403000"}' },
    UNKNOWN_ERROR = { error_code = "503000", message = '{"message":"Could not validate API KEY","error_code":"503000"}' },
    INVALID_KEY = { error_code = "403003", message = '{"message":"Api KEY is invalid","error_code":"403003"}' }
}

beforeEach(function()
    BaseValidatorMock = mock("api-gateway.validation.validator", {
        "new", "exitFn", "getKeyFromLocalCache", "setContextProperties",
        "getKeyFromRedis", "setKeyInLocalCache"
    })
    RedisConnectionProviderMock = mock("api-gateway.redis.redisConnectionProvider", {
        "new", "getConnection", "closeConnection"
    })
    ngx.HTTP_SERVICE_UNAVAILABLE = 503
    ngx.HTTP_NOT_FOUND = 404

    BaseValidatorMock.__exitFn.doReturn = function(self, arg1, arg2)
        return arg1, arg2
    end
end)

test('validateRequest: should return 403000 if api key is missing', function()
    -- given
    ngx.var.api_key = nil
    ngx.var.service_id = "test-service"

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local error_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(error_code, EXPECTED_RESPONSES.MISSING_KEY.error_code)
    assertEquals(response_body, EXPECTED_RESPONSES.MISSING_KEY.message)

    calls(BaseValidatorMock.__exitFn, 1, EXPECTED_RESPONSES.MISSING_KEY.error_code, EXPECTED_RESPONSES.MISSING_KEY.message)
end)

test('validateRequest: should return OK and skip searching in redis if api key is in local cache', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return '{"key": "test-api-key", "realm": "sandbox", "service_id": "test-service", "service_name": "test-service-name"}'
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(ngx.HTTP_OK, response_code)
    assertEquals('{"valid":true}', response_body)

    calls(BaseValidatorMock.__exitFn, 1, ngx.HTTP_OK, '{"valid":true}')
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__getKeyFromRedis, 0)

    local expected_api_key_object = cjson.decode('{"key": "test-api-key", "realm": "sandbox", "service_id": "test-service", "service_name": "test-service-name"}')
    calls(BaseValidatorMock.__setContextProperties, 1, expected_api_key_object)

end)

test('validateRequest: should return OK and search in redis if api key is not in local cache and redis hash has metadata field', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return '{"key": "test-api-key", "realm": "sandbox", "service_id": "test-service", "service_name": "test-service-name"}'
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, ngx.HTTP_OK)
    assertEquals(response_body, '{"valid":true}')

    calls(BaseValidatorMock.__exitFn, 1, ngx.HTTP_OK, '{"valid":true}')
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__setKeyInLocalCache, 1)
    calls(BaseValidatorMock.__getKeyFromRedis, 1)

    local expected_api_key_object = cjson.decode('{"key": "test-api-key", "realm": "sandbox", "service_id": "test-service", "service_name": "test-service-name"}')
    calls(BaseValidatorMock.__setContextProperties, 1, expected_api_key_object)
end)

test('validateRequest: should return OK and search in redis for the old format if api key is not in local cache and redis hash does not have metadata field', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return nil
    end

    RedisConnectionProviderMock.__getConnection.doReturn = function()
        local redis = {}
        redis.hmget = function (redis_key, ...)
            return {"test-api-key", "sandbox", "test-service", "test-service-name"}, nil
        end

        return true, redis
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, ngx.HTTP_OK)
    assertEquals(response_body, '{"valid":true}')

    calls(BaseValidatorMock.__exitFn, 1, ngx.HTTP_OK, '{"valid":true}')
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__setKeyInLocalCache, 1)
    calls(BaseValidatorMock.__getKeyFromRedis, 1)
    calls(RedisConnectionProviderMock.__getConnection, 1)
    calls(RedisConnectionProviderMock.__closeConnection, 1)

    local expected_api_key_object = cjson.decode('{"key": "test-api-key", "realm": "sandbox", "service_id": "test-service", "service_name": "test-service-name"}')
    calls(BaseValidatorMock.__setContextProperties, 1, expected_api_key_object)
end)

test('validateRequest: should return 503000 if api key is not in local cache and connecting to redis fails', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return nil
    end

    RedisConnectionProviderMock.__getConnection.doReturn = function()
        local redis = {}
        redis.hmget = function (redis_key, ...)
            return {"test-api-key", "sandbox", "test-service", "test-service-name"}, nil
        end

        return false, redis
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, EXPECTED_RESPONSES.UNKNOWN_ERROR.error_code)
    assertEquals(response_body, EXPECTED_RESPONSES.UNKNOWN_ERROR.message)

    calls(BaseValidatorMock.__exitFn, 1, EXPECTED_RESPONSES.UNKNOWN_ERROR.error_code, EXPECTED_RESPONSES.UNKNOWN_ERROR.message)
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__getKeyFromRedis, 1)
    calls(RedisConnectionProviderMock.__getConnection, 1)

    calls(BaseValidatorMock.__setKeyInLocalCache, 0)
    calls(RedisConnectionProviderMock.__closeConnection, 0)
    calls(BaseValidatorMock.__setContextProperties, 0)
end)

test('validateRequest: should return 503000 if api key is not in local cache and redis operation returns an error', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return nil
    end

    RedisConnectionProviderMock.__getConnection.doReturn = function()
        local redis = {}
        redis.hmget = function (redis_key, ...)
            return nil, "error"
        end

        return true, redis
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, EXPECTED_RESPONSES.UNKNOWN_ERROR.error_code)
    assertEquals(response_body, EXPECTED_RESPONSES.UNKNOWN_ERROR.message)

    calls(BaseValidatorMock.__exitFn, 1, EXPECTED_RESPONSES.UNKNOWN_ERROR.error_code, EXPECTED_RESPONSES.UNKNOWN_ERROR.message)
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__getKeyFromRedis, 1)
    calls(RedisConnectionProviderMock.__getConnection, 1)

    calls(BaseValidatorMock.__setKeyInLocalCache, 0)
    calls(RedisConnectionProviderMock.__closeConnection, 1)
    calls(BaseValidatorMock.__setContextProperties, 0)
end)

test('validateRequest: should return 403003 if api key is not in local cache and redis operation returns a nil value', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return nil
    end

    RedisConnectionProviderMock.__getConnection.doReturn = function()
        local redis = {}
        redis.hmget = function (redis_key, ...)
            return nil, nil
        end

        return true, redis
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, EXPECTED_RESPONSES.INVALID_KEY.error_code)
    assertEquals(response_body, EXPECTED_RESPONSES.INVALID_KEY.message)

    calls(BaseValidatorMock.__exitFn, 1, EXPECTED_RESPONSES.INVALID_KEY.error_code, EXPECTED_RESPONSES.INVALID_KEY.message)
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__getKeyFromRedis, 1)
    calls(RedisConnectionProviderMock.__getConnection, 1)
    calls(RedisConnectionProviderMock.__closeConnection, 1)

    calls(BaseValidatorMock.__setKeyInLocalCache, 0)
    calls(BaseValidatorMock.__setContextProperties, 0)
end)

test('validateRequest: should return 403003 if api key is not in local cache and redis entry in an empty table', function()
    -- given
    ngx.var.api_key = "test-api-key"
    ngx.var.service_id = "test-service"

    BaseValidatorMock.__getKeyFromLocalCache.doReturn = function()
        return nil
    end

    BaseValidatorMock.__getKeyFromRedis.doReturn = function()
        return nil
    end

    RedisConnectionProviderMock.__getConnection.doReturn = function()
        local redis = {}
        redis.hmget = function (redis_key, ...)
            return {}, nil
        end

        return true, redis
    end

    -- when
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()
    local response_code, response_body = classUnderTest:validateRequest()

    -- then
    assertEquals(response_code, EXPECTED_RESPONSES.INVALID_KEY.error_code)
    assertEquals(response_body, EXPECTED_RESPONSES.INVALID_KEY.message)

    calls(BaseValidatorMock.__exitFn, 1, EXPECTED_RESPONSES.INVALID_KEY.error_code, EXPECTED_RESPONSES.INVALID_KEY.message)
    calls(BaseValidatorMock.__getKeyFromLocalCache, 1, "test-api-key:test-service", "cachedkeys")
    calls(BaseValidatorMock.__getKeyFromRedis, 1)
    calls(RedisConnectionProviderMock.__getConnection, 1)
    calls(RedisConnectionProviderMock.__closeConnection, 1)

    calls(BaseValidatorMock.__setKeyInLocalCache, 0)
    calls(BaseValidatorMock.__setContextProperties, 0)
end)