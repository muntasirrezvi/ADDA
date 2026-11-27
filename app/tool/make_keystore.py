"""Builds Adda's release signing key from the ADDA_SIGN_SEED secret.

The same seed always gives the same key and certificate, so every APK is signed the same way
and installs over the previous one. Nothing secret is stored in the repository.
Usage: ADDA_SIGN_SEED=... ADDA_KEY_PASS=... python3 make_keystore.py out.p12
"""
import datetime, hashlib, hmac, os, sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID


class Drbg:
    def __init__(self, seed: bytes):
        self.key, self.n = hashlib.sha256(b"adda-sign-v1" + seed).digest(), 0

    def bytes(self, k):
        out = b""
        while len(out) < k:
            self.n += 1
            out += hmac.new(self.key, self.n.to_bytes(8, "big"), hashlib.sha256).digest()
        return out[:k]

    def below(self, n):
        return int.from_bytes(self.bytes((n.bit_length() + 7) // 8 + 8), "big") % n


SMALL = [p for p in range(3, 2000) if all(p % q for q in range(2, int(p ** 0.5) + 1))]


def is_prime(n, rng):
    if any(n % p == 0 for p in SMALL):
        return n in SMALL
    d, s = n - 1, 0
    while d % 2 == 0:
        d, s = d // 2, s + 1
    for _ in range(40):
        a = 2 + rng.below(n - 3)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def prime(bits, rng, e=65537):
    while True:
        c = int.from_bytes(rng.bytes(bits // 8), "big") | (3 << (bits - 2)) | 1
        if (c - 1) % e and is_prime(c, rng):
            return c


def main():
    seed = os.environ["ADDA_SIGN_SEED"].encode()
    pw = os.environ["ADDA_KEY_PASS"].encode()
    rng = Drbg(seed)
    e = 65537
    p, q = prime(1536, rng), prime(1536, rng)
    if p < q:
        p, q = q, p
    n, phi = p * q, (p - 1) * (q - 1)
    d = pow(e, -1, phi)
    key = rsa.RSAPrivateNumbers(p, q, d, d % (p - 1), d % (q - 1), pow(q, -1, p), rsa.RSAPublicNumbers(e, n)).private_key()
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Adda"), x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Riot"), x509.NameAttribute(NameOID.COUNTRY_NAME, "BD")])
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(int.from_bytes(hashlib.sha256(str(n).encode()).digest()[:16], "big") >> 1)
            .not_valid_before(datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
            .not_valid_after(datetime.datetime(2076, 1, 1, tzinfo=datetime.timezone.utc))
            .sign(key, hashes.SHA256()))  # RSA PKCS#1 v1.5: same input, same signature
    data = pkcs12.serialize_key_and_certificates(b"adda", key, cert, None, serialization.BestAvailableEncryption(pw))
    open(sys.argv[1], "wb").write(data)
    print("certificate sha256:", cert.fingerprint(hashes.SHA256()).hex()[:16] + "...")


main()
