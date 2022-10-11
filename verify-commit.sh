#!/bin/bash

# Git Log Formats Cheatsheet
# https://devhints.io/git-log-format


function show_help() {
    echo "A commit was found without a signature or with an invalid one"
    echo "Use the following command to automatically resign your branch:"
    echo "    git rebase master -x 'git commit --allow-empty --amend -S --no-edit'"
}

# ===================================
# Globals
# ===================================

# Get Commit Hash
COMMIT_HASH=${1:-HEAD}
echo "[>] Checking commit '$COMMIT_HASH'"

# Extract Commit Author's email
COMMIT_EMAIL="$(git log -1 --pretty=format:'%ae')"

# Use gitsign to verify signature
VERIFY_COMMIT="$(git verify-commit -v $COMMIT_HASH 2>&1)"

# Extract email of SigningCertificate (obtained through OIDC)
SIGNER="$(echo $VERIFY_COMMIT | grep 'gitsign: Good signature from' | sed 's/.*\[\([^]]*\)\].*/\1/g')"

# Extract PKCS signature:
# https://github.com/sigstore/gitsign/tree/v0.3.1#inspecting-the-git-commit-signature
COMMIT_SIGNATURE="$(git cat-file commit $COMMIT_HASH | sed -n '/BEGIN/, /END/p' | sed 's/^ //g' | sed 's/gpgsig //g' | sed 's/SIGNED MESSAGE/PKCS7/g')"

# Extract ConnectorID by parsing PKCS#7 format (openssl does not support it)
PKCS7_FIELD_CONNECTOR_ID="1.3.6.1.4.1.57264.1.1"
CONNECTOR_ID="$(openssl pkcs7 -in <(echo "${COMMIT_SIGNATURE}") -print | grep $PKCS7_FIELD_CONNECTOR_ID -A6 | grep 'value:' -A5 | grep 0000 -A2 | sed 's/^.*- \(.*\)  .*$/\1/g' | tr '-' ' ' | tr -d '\n ' | xxd -p -r | strings)"

# ===================================
# Validations
# ===================================

echo "[*] Verifying author '$COMMIT_EMAIL'"

# Validate that the commit is signed
if [ -z "$SIGNER" ]; then
	echo "[-] Commit is NOT signed!"
	exit 101
fi

# Validate that the signer is the commit author
echo -n "[!] Commit Author Email: '$COMMIT_EMAIL' - Signed by '$SIGNER'... "
if [ "$SIGNER" = "$COMMIT_EMAIL" ]; then
	echo "match"
else
	echo "NO match"
	exit 102
fi

# Validate if signer's email is allowed to commit
valid_domain=0
if [ ! -z "$EMAIL_DOMAINS" ]; then
	echo "[*] Verifying author ('$COMMIT_EMAIL') against following domains: [${EMAIL_DOMAINS}]"
	for domain in ${EMAIL_DOMAINS}; do
		if [[ "$COMMIT_EMAIL" =~ "@${domain}" ]]; then
			echo "[+] Author's email domain found: '$domain'"
			valid_domain=1
			break
		fi
	done

	if [ $valid_domain = 0 ]; then
		echo "[-] Commit author's domain is not allowed ('$COMMIT_EMAIL')"
		exit 103
	fi
fi

valid_connID=0
if [ ! -z "$ACCEPTED_CONNECTOR_IDS" ]; then
	echo "[*] Verifying authentication from trusted ConnectorIDs: [${ACCEPTED_CONNECTOR_IDS}]"
	for connID in ${ACCEPTED_CONNECTOR_IDS}; do
		if [ "$CONNECTOR_ID" = "${connID}" ]; then
			echo "[+] Author's ConnectorID found: '$connID'"
			valid_connID=1
			break
		fi
	done

	if [ $valid_connID = 0 ]; then
		echo "[-] Author's ConnectorID is not allowed ('$CONNECTOR_ID')"
		exit 104
	fi

fi


exit 0
