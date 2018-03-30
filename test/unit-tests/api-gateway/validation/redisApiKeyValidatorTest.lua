---
--- Created by purcarea.
--- DateTime: 30/03/2018
---

local BaseValidatorMock = mock("api-gateway.validation.validator", {
    "new"
})

test('no test', function()
    local classUnderTest = require('api-gateway.validation.key.redisApiKeyValidator'):new()

end)