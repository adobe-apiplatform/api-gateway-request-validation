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

local aes = require"resty.aes"
local str = require "resty.string"

local Hasher = {}

function Hasher:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local salt = "API-Gateway-Salt!"

---
-- Encrypts the plain_text with a specific salt using the SHA256 algorithm.
-- @param plain_text The Text to encode
-- @param seed_text A starting point for the encryption algorithm
-- @return - the encrypted text
--
function Hasher:encryptText(plain_text, seed_text)
    local aes_256_cbc_sha512x5 = aes:new(seed_text,
        salt,
        aes.cipher(256, "cbc"),
        aes.hash.sha512, 5)
    -- AES 256 CBC with 5 rounds of SHA-512 for the key
    -- and a salt of "API-Gateway-Salt!"
    local encrypted = aes_256_cbc_sha512x5:encrypt(plain_text)
    return str.to_hex(encrypted)
end

---
-- Decrypts the cipher_text with a specific salt using the SHA256 algorithm.
-- @param cypher_text The Text to encode
-- @param seed_text A starting point for the encryption algorithm - The same seed used in the encyption phase
-- @return - the decrypted text
--
function Hasher:decryptText(cipher_text, seed_text)
    local aes_256_cbc_sha512x5 = aes:new(seed_text,
        salt,
        aes.cipher(256, "cbc"),
        aes.hash.sha512, 5)
    local decrypted = aes_256_cbc_sha512x5:decrypt(cipher_text)
    return str.to_hex(decrypted)
end

return Hasher



