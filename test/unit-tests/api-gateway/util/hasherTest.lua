---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by trifan.
--- DateTime: 11/04/2018 10:13
---
local restyStringMock = mock("resty.string", {"to_hex"})
local sha256Mock = mock("resty.sha256", {"new", "update", "final"})
local sha224Mock = mock("resty.sha224", {"new", "update", "final"})
local sha512Mock = mock("resty.sha512", {"new", "update", "final"})
local sha384Mock = mock("resty.sha384", {"new", "update", "final"})

beforeEach(function()
    ngx.var.hashing_algorithm = nil
    when(sha256Mock).final.fake(function(self, str)
        return "sha256"
    end)

    when(sha224Mock).final.fake(function(self, str)
        return "sha224"
    end)

    when(sha512Mock).final.fake(function(self, str)
        return "sha512"
    end)

    when(sha384Mock).final.fake(function(self, str)
        return "sha384"
    end)

    when(restyStringMock).to_hex.fake(function(digest)
        return digest
    end)
end)


test('missing algorithm should fall to sha256', function()
    local classUnderTest = require("api-gateway.util.hasher")
    local result = classUnderTest.hash("test")
    assertEquals(result, "sha256")
end)

test('wrong algorithm should fall to sha256', function()
    ngx.var.hashing_algorithm = "sha1101"
    local classUnderTest = require("api-gateway.util.hasher")
    local result = classUnderTest.hash("test")
    assertEquals(result, "sha256")
end)

test('correct algorithm should require the desired alg', function()
    local classUnderTest = require("api-gateway.util.hasher")

    ngx.var.hashing_algorithm = "sha256"
    local result = classUnderTest.hash("test")
    assertEquals(result, "sha256")


    ngx.var.hashing_algorithm = "sha512"
    result = classUnderTest.hash("test")
    assertEquals(result, "sha512")


    ngx.var.hashing_algorithm = "sha224"
    result = classUnderTest.hash("test")
    assertEquals(result, "sha224")


    ngx.var.hashing_algorithm = "sha384"
    result = classUnderTest.hash("test")
    assertEquals(result, "sha384")
end)