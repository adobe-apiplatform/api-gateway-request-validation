package = "api-gateway-request-validation"
version = "1.3.12-1"
source = {
   url = "git://github.com/adobe-apiplatform/api-gateway-request-validation.git",
   tag = "api-gateway-request-validation-1.3.12"
}
description = {
   summary = "Lua Module providing a request validation framework in the API Gateway.",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1", "lua-api-gateway-hmac >= 1.0.0"
}
build = {
   type = "builtin",
   platforms = {
      haiku = {
         modules = {
            ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
            ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
            ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
            ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
            ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
            ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
            ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
            ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
            ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
            ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
            ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
            ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
            ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
            ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
            ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
         }
      },
      macosx = {
         modules = {
            ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
            ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
            ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
            ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
            ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
            ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
            ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
            ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
            ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
            ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
            ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
            ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
            ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
            ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
            ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
         }
      },
      mingw32 = {
         modules = {
            ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
            ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
            ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
            ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
            ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
            ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
            ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
            ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
            ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
            ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
            ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
            ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
            ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
            ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
            ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
         }
      },
      unix = {
         modules = {
            ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
            ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
            ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
            ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
            ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
            ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
            ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
            ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
            ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
            ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
            ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
            ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
            ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
            ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
            ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
         }
      },
      win32 = {
         modules = {
            ["api-gateway.dogstatsd.Dogstatsd"] = "src/lua/api-gateway/dogstatsd/Dogstatsd.lua",
            ["api-gateway.redis.redisConnectionConfiguration"] = "src/lua/api-gateway/redis/redisConnectionConfiguration.lua",
            ["api-gateway.redis.redisConnectionProvider"] = "src/lua/api-gateway/redis/redisConnectionProvider.lua",
            ["api-gateway.redis.redisHealthCheck"] = "src/lua/api-gateway/redis/redisHealthCheck.lua",
            ["api-gateway.util.OauthClient"] = "src/lua/api-gateway/util/OauthClient.lua",
            ["api-gateway.util.logger"] = "src/lua/api-gateway/util/logger.lua",
            ["api-gateway.validation.base"] = "src/lua/api-gateway/validation/base.lua",
            ["api-gateway.validation.factory"] = "src/lua/api-gateway/validation/factory.lua",
            ["api-gateway.validation.key.redisApiKeyValidator"] = "src/lua/api-gateway/validation/key/redisApiKeyValidator.lua",
            ["api-gateway.validation.oauth2.oauthTokenValidator"] = "src/lua/api-gateway/validation/oauth2/oauthTokenValidator.lua",
            ["api-gateway.validation.oauth2.userProfileValidator"] = "src/lua/api-gateway/validation/oauth2/userProfileValidator.lua",
            ["api-gateway.validation.signing.hmacGenericSignatureValidator"] = "src/lua/api-gateway/validation/signing/hmacGenericSignatureValidator.lua",
            ["api-gateway.validation.validator"] = "src/lua/api-gateway/validation/validator.lua",
            ["api-gateway.validation.validatorsHandler"] = "src/lua/api-gateway/validation/validatorsHandler.lua",
            ["api-gateway.validation.validatorsHandlerErrorDecorator"] = "src/lua/api-gateway/validation/validatorsHandlerErrorDecorator.lua"
         }
      }
   }
}
