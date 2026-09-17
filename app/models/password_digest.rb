require "openssl"

# Password hashing compatible with the format already stored in the database:
#   pbkdf2_sha256$<iterations>$<salt hex>$<derived key hex>
# Keeping the same scheme means accounts created before the rewrite can still
# sign in.
module PasswordDigest
  ITERATIONS = 200_000
  KEY_LENGTH = 32

  def self.hash(password)
    salt = OpenSSL::Random.random_bytes(16)
    digest = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, ITERATIONS, KEY_LENGTH, "sha256")
    "pbkdf2_sha256$#{ITERATIONS}$#{salt.unpack1('H*')}$#{digest.unpack1('H*')}"
  end

  def self.verify(password, stored)
    algo, iterations, salt_hex, hash_hex = stored.to_s.split("$")
    return false unless algo == "pbkdf2_sha256" && salt_hex && hash_hex

    salt = [ salt_hex ].pack("H*")
    expected = [ hash_hex ].pack("H*")
    actual = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations.to_i, expected.bytesize, "sha256")
    # Constant-time comparison so a wrong password cannot be distinguished by timing.
    OpenSSL.fixed_length_secure_compare(actual, expected)
  rescue ArgumentError
    false
  end

  def self.valid_format?(stored)
    stored.to_s.split("$").length == 4
  end
end