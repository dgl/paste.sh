/**
 * OpenSSL style PBKDF2.
 */
var OpenSSLPbkdf2 = {
  /**
   * Derives a key and IV from a password.
   *
   * @param {string} password The password to derive from.
   * @param {number} keySize The size in words of the key to generate.
   * @param {number} ivSize The size in words of the IV to generate.
   * @param {WordArray|string} salt (Optional) A 64-bit salt to use. If omitted, a salt will be generated randomly.
   *
   * @return {CipherParams} A cipher params object with the key, IV, and salt.
   *
   * @static
   *
   */
  execute: function (password, keySize, ivSize, salt, hasher) {
    // Generate random salt
    if (!salt) {
      salt = CryptoJS.lib.WordArray.random(64 / 8);
    }

    // Derive key and IV
    var key = CryptoJS.algo.PBKDF2.create({
      keySize: keySize + ivSize,
      hasher: hasher,
    }).compute(password, salt);

    // Separate key and IV
    var iv = CryptoJS.lib.WordArray.create(
      key.words.slice(keySize),
      ivSize * 4,
    );
    key.sigBytes = keySize * 4;

    // Return params
    return CryptoJS.lib.CipherParams.create({ key: key, iv: iv, salt: salt });
  },
};
