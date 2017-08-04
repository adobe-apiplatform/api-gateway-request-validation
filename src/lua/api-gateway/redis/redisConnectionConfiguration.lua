--
-- Created by IntelliJ IDEA.
-- User: vdatcu
-- Date: 04/08/2017
-- Time: 11:54
-- To change this template use File | Settings | File Templates.
--


local redisConf = {}

redisConf["oauth"] = {
    env_password_variable = "REDIS_PASS_OAUTH",
    ro_upstream_name = "oauth-redis-ro-upstream",
    rw_upstream_name = "oauth-redis-rw-upstream"
}

redisConf["apiKey"] = {
    env_password_variable = "REDIS_PASS_API_KEY",
    ro_upstream_name = "api-gateway-redis-replica",
    rw_upstream_name = "api-gateway-redis"
}

return redisConf