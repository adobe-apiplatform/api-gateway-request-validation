package="api-gateway-request-validation"
version="1.3.10-2"
local function make_plat(plat)
    return { modules = {
        ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
        ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
        ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
        ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
        ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
        ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
        ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
        ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
        ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
        ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
        ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
        ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
        ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
        ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
        ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
    } }
end
source = {
    url = "https://github.com/adobe-apiplatform/api-gateway-request-validation.git",
    tag = "api-gateway-request-validation-1.3.10"
}
description = {
    summary = "Lua Module providing a request validation framework in the API Gateway.",
    license = "MIT"
}
dependencies = {
    "lua > 5.1"
}
build = {
    type = "builtin",
    platforms = {
        unix = make_plat("unix"),
        macosx = make_plat("macosx"),
        haiku = make_plat("haiku"),
        win32 = make_plat("win32"),
        mingw32 = make_plat("mingw32")
    }
}
