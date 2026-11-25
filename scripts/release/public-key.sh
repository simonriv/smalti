#!/usr/bin/env bash
# F7.6: the EdDSA public key (base64, as SUPublicEDKey) of the private seed on stdin (generate_keys -x format).
set -euo pipefail
python3 -c '
import base64, subprocess, sys
seed = base64.b64decode(sys.stdin.read().strip())
if len(seed) != 32:
    sys.exit("the private key must be a 32-byte ed25519 seed")
der = bytes.fromhex("302e020100300506032b657004220420") + seed
pem = b"-----BEGIN PRIVATE KEY-----\n" + base64.b64encode(der) + b"\n-----END PRIVATE KEY-----\n"
out = subprocess.run(["openssl", "pkey", "-pubout", "-outform", "DER"], input=pem, capture_output=True, check=True)
print(base64.b64encode(out.stdout[-32:]).decode())
'
