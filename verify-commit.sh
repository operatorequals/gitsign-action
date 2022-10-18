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
INPUT=${1:-HEAD}

# Extract Commit Hash
COMMIT_HASH="$(git log -1 $INPUT --pretty=format:'%h')"
echo "[>] Checking commit '$COMMIT_HASH'"

# Extract Commit Author's email
COMMIT_EMAIL="$(git log -1 $COMMIT_HASH --pretty=format:'%ce')"

# Extract Commit Author Date as Unix Timestamp
COMMIT_DATE_U="$(git log -1 $COMMIT_HASH --pretty=format:'%at')"

# Also get Commit Author Date in GMT (to match SigningCertificate dates)
COMMIT_DATE="$(TZ="GMT" git log -1 $COMMIT_HASH --pretty=format:'%ad' --date='local' ) $TZ"

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

# Extract SigningCertificate Validity Period (format: '%b %d %T %Y' GMT)
DATE_NOT_BEFORE="$(openssl pkcs7 -in <(echo "${COMMIT_SIGNATURE}") -print | grep validity -A2 | grep 'notBefore' | cut -d ':' -f 2-)"
DATE_NOT_AFTER="$(openssl pkcs7 -in <(echo "${COMMIT_SIGNATURE}") -print | grep validity -A2 | grep 'notAfter' | cut -d ':' -f 2-)"

# Convert Dates to Unix Timestamps
DATE_NOT_BEFORE_U="$(date +%s --date="${DATE_NOT_BEFORE}")"
DATE_NOT_AFTER_U="$(date +%s --date="${DATE_NOT_AFTER}")"

# ===================================
# Validations
# ===================================


# Validate that the commit is signed
if [ -z "$SIGNER" ]; then
	echo "[-][$COMMIT_HASH] Commit is NOT signed!"
	exit 101
fi

# Validate that the signer is the commit author
echo "[*][$COMMIT_HASH] Verifying author '$COMMIT_EMAIL'"
if [ "$SIGNER" = "$COMMIT_EMAIL" ]; then
	echo "[+][$COMMIT_HASH] Signed by '$SIGNER' (matching commit author)"
else
	echo "[-][$COMMIT_HASH] Signed by '$SIGNER'. Commit author '$COMMIT_EMAIL' does NOT match"
	exit 102
fi

# Validate if signer's email is allowed to commit
valid_domain=0
if [ ! -z "$EMAIL_DOMAINS" ]; then
	echo "[*][$COMMIT_HASH] Verifying author ('$COMMIT_EMAIL') against following domains: [${EMAIL_DOMAINS}]"
	for domain in ${EMAIL_DOMAINS}; do
		if [[ "$COMMIT_EMAIL" =~ "@${domain}" ]]; then
			echo "[+][$COMMIT_HASH] Author's email domain found: '$domain'"
			valid_domain=1
			break
		fi
	done

	if [ $valid_domain = 0 ]; then
		echo "[-][$COMMIT_HASH] Commit author's domain is not allowed ('$COMMIT_EMAIL')"
		exit 103
	fi
fi

valid_connID=0
if [ ! -z "$ACCEPTED_CONNECTOR_IDS" ]; then
	echo "[*][$COMMIT_HASH] Verifying authentication from trusted ConnectorIDs: [${ACCEPTED_CONNECTOR_IDS}]"
	for connID in ${ACCEPTED_CONNECTOR_IDS}; do
		if [ "$CONNECTOR_ID" = "${connID}" ]; then
			echo "[+][$COMMIT_HASH] Author's ConnectorID found: '$connID'"
			valid_connID=1
			break
		fi
	done

	if [ $valid_connID = 0 ]; then
		echo "[-][$COMMIT_HASH] Author's ConnectorID is not allowed ('$CONNECTOR_ID')"
		exit 104
	fi
fi

if [ "$CHECK_SIGNING_DATE" = true ]; then
	echo "[*][$COMMIT_HASH] Verifying Commit Date is in SigningCertificate's Validity Period"
	# echo "[@] ${DATE_NOT_BEFORE_U} <= ${COMMIT_DATE_U} <= ${DATE_NOT_AFTER_U}" # Debug

	if [ "$COMMIT_DATE_U" -lt "$DATE_NOT_BEFORE_U" ]; then
		echo "[-][$COMMIT_HASH] Commit date '${COMMIT_DATE}' is BEFORE [${DATE_NOT_BEFORE}, ${DATE_NOT_AFTER}]"
		exit 110
	fi
	if [ "$COMMIT_DATE_U" -gt "$DATE_NOT_AFTER_U" ]; then
		echo "[-][$COMMIT_HASH] Commit date '${COMMIT_DATE}' is AFTER [${DATE_NOT_BEFORE}, ${DATE_NOT_AFTER}]"
		exit 111
	fi

	echo "[+][$COMMIT_HASH] Commit date: '${COMMIT_DATE}' is in [${DATE_NOT_BEFORE}, ${DATE_NOT_AFTER}]"
fi

exit 0
