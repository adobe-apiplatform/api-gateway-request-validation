--
-- Created by IntelliJ IDEA.
-- User: purcarea
-- Date: 30/03/18
--
local tests = {
    "test.unit-tests.api-gateway.validation.redisApiKeyValidatorTest",
    "test.unit-tests.api-gateway.util.hasherTest",
    "test.unit-tests.api-gateway.validation.oauth2.oauthTokenValidatorTest"
}

require("mocka.suite")(tests)
