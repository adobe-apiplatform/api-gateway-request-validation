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

local str = require "resty.string"

---
-- Encrypts the plain_text using an algoithm specified via a Chef env variable - SHA256 is the default.
-- Possible values: sha256, sha224, sha512, sha384
-- @param plain_text The Text to encode
-- @return - the encrypted text
--
local function _hash(plain_text)
    local algorithm = ngx.var.hashing_algorithm
    if (algorithm == nil or algorithm == '') then
        ngx.log(ngx.INFO, "No hashing algorithm has been passed. Dafualting to SHA256")
        algorithm = "sha256"
    end
    if (algorithm ~= "sha256" or algorithm ~= "sha224" or algorithm ~= "sha512" or algorithm ~= "sha384") then
        ngx.log(ngx.INFO, "The hashing algorithm passed is invalid. Dafualting to SHA256")
        algorithm = "sha256"
    end

    local restySha =  require ("resty." .. algorithm)
    local sha = restySha:new()
    sha:update(plain_text)
    local digest = sha:final()
    return str.to_hex(digest)
end

return {
    hash = _hash
}