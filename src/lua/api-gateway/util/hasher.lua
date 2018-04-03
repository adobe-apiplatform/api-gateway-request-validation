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

local resty_sha256 = require "resty.sha256"
local str = require "resty.string"

local Hasher = {}

function Hasher:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- Encrypts the plain_text with a specific salt using the SHA256 algorithm.
-- @param plain_text The Text to encode
-- @return - the encrypted text
--
function Hasher:hash(plain_text)
    local sha256 = resty_sha256:new()
    sha256:update(plain_text)
    local digest = sha256:final()
    ngx.log(ngx.DEBUG, "Hashed ", plain_text, " - ", digest)
    return str.to_hex(digest)
end

return Hasher