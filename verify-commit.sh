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

# Extract Commit Author's email
COMMIT_HASH=${1:-HEAD}
echo "[>] Checking commit '$COMMIT_HASH'"

# Extract Commit Author's email
COMMIT_EMAIL="$(git log -1 --pretty=format:'%ae')"

# Use gitsign to verify signature
VERIFY_COMMIT="$(git verify-commit -v $COMMIT_HASH 2>&1)"

# Extract email of SigningCertificate (obtained through OIDC)
SIGNER="$(echo $VERIFY_COMMIT | grep 'gitsign: Good signature from' | sed 's/.*\[\([^]]*\)\].*/\1/g')"

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
	for domain in "$EMAIL_DOMAINS"; do
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

exit 0
