--
-- Created by IntelliJ IDEA.
-- User: purcarea
-- Date: 30/03/18
--
local tests = {
    "test.unit-tests.api-gateway.validation.redisApiKeyValidatorTest",
    "test.unit-tests.api-gateway.util.hasherTest"
}

require("mocka.suite")(tests)
