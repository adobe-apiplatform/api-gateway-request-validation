--
-- Created by IntelliJ IDEA.
-- User: vdatcu
-- Date: 04/08/2017
-- Time: 11:54
-- To change this template use File | Settings | File Templates.
--

local RedisConnectionConfiguration = {}

local redisConf = {
    ["oauth"] = {
        env_password_variable = "REDIS_PASS_OAUTH",
        ro_upstream_name = "oauth-redis-ro-upstream",
        rw_upstream_name = "oauth-redis-rw-upstream"
    },
    ["apiKey"] = {
        env_password_variable = "REDIS_PASS_API_KEY",
        ro_upstream_name = "api-gateway-redis-replica",
        rw_upstream_name = "api-gateway-redis"
    }
}

function RedisConnectionConfiguration:getApiKeyConfiguration()
    return redisConf.apiKey
end

function RedisConnectionConfiguration:getOauthConfiguration()
    return redisConf.oauth
end

return RedisConnectionConfiguration