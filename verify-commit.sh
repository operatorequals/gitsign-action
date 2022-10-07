#!/bin/sh

# Git Log Formats Cheatsheet
# https://devhints.io/git-log-format

# Extract Commit Author's email
COMMIT_HASH="$(git log -1 --pretty=format:'%H')"
echo "[+] Checking commit '$COMMIT_HASH'"

# Extract Commit Author's email
COMMIT_EMAIL="$(git log -1 --pretty=format:'%ae')"

# Use gitsign to verify signature
VERIFY_COMMIT="$(git verify-commit -v HEAD 2>&1)"

# Extract email of SigningCertificate (obtained through OIDC)
SIGNER="$(echo $VERIFY_COMMIT | grep 'gitsign: Good signature from' | sed 's/.*\[\([^]]*\)\].*/\1/g')"

echo -n "[!] Commit Author Email: '$COMMIT_EMAIL' - Signed by '$SIGNER'... "

# Validate that the signer is the commit author
if [ "$SIGNER" = "$COMMIT_EMAIL" ]; then
	echo "match"
	exit 0
else
	echo "NO match"
	echo "[-] Aborting git rebase!"
	git rebase --abort
	exit 101
fi

git rebase --abort
exit 255
