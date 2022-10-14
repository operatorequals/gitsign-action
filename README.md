# gitsign-action

This Github Action verifies [Sigstore `gitsign`](https://github.com/sigstore/gitsign) key-less commit signatures for a chain of commits.

## Verifications

The Github Action verifies that all commits between `HEAD` and the git ref specified in the `ref` input:

* Are *signed* by the `gitsign` tool
* The signer's name (the `SigningCertificate`'s `X509v3 SAN:email`) is the same with the git commit's author email
* The Identity Provider URL used by the signer to provide the `email` to Fulcio is one of the [SigStore trusted IdPs (Github, Google, Microsoft)](https://github.com/sigstore/gitsign/tree/master#file-config) (changeable through `connector-ids` input)
* If the `email-domains` input is set - the signer's email domain is in the `email-domains` list
* If the `check-signing-date` input is set to `true` - the commit date falls in the `SigningCertificate`'s Validity Period (`Cert NotBefore` <= `Commit Date` <= `Cert Not After`).

## How it works

The Github Action loops through the commits between `ref` input and `HEAD`.
If a non-verifiable commit is found, the Github Action fails and reports which commit failed to verify.

```
[commit+N] {branch1} (checked) <-- Action runs in this commit
  |
  v
[commit+N-1] (checked)
  |
  v
[...] (checked)
  |
  v
[commit+1] (checked)
  |
  v
[commit] {ref=master}
```

## Usage

```yaml
[...]

jobs:
  check-signatures:
    runs-on: "ubuntu-latest"

    steps:
    - name: Checkout repository
      uses: actions/checkout@v3

    - name: Check Signatures
      uses: operatorequals/gitsign-action@master
      with:
        version: '0.3.1'  # default '0.3.1'
        ref: master	      # default 'origin/master'
        email-domains: "gmail.com users.noreply.github.com" # default ''
        connector-ids: "https://github.com/login/oauth https://accounts.google.com" # default 'Github, Google, Microsoft'

```

## Enable `Gitsign` for a repository

Gitsign configuration can be found in [repository's `README.md`](https://github.com/sigstore/gitsign#configuration)


## Scenarios mitigated by Sigstore Gitsign along with this Github Action

An adversary with access to a repository under `example.com`...

### Does not sign a commit

If an unsigned commit gets checked, this action will directly stop with an error.

### Pushes a Git commit as `jdoe@example.com` and signs with email `random091[...]74@gmail.com`

As (as of now) `gitsign verify` does only check if a commit signature exists, this would pass `git verify-commit <commit-id>`
 command (https://github.com/sigstore/gitsign/issues/104).
 Yet, This Github Action does validate that commit author and and email found in the `SigningCertificate` are the same string.

### Pushes a Git commit with author email same with signing email `random091[...]74@gmail.com`

This scenario would pass if `email-domains` is not set in this Action. If `email-domains: "example.com"` is in place,
this Action will fail if the commiter/issuer email domain is not `example.com`.

### Fetches a `SigningCertificate` from a custom [`Fulcio`](https://github.com/sigstore/fulcio) instance

The `SigningCertificate` can contain both `jdoe@example.com` and the correct `ConnectorID` as they are signed by a CA controlled by the adversary.

Yet, such Certificate is not signed by SigStore's Public CA, and the `gitsign` verification command is set to verify Certificate's from SigStore's Fulcio Public CA only (controlled by `GITSIGN_FULCIO_URL` (https://github.com/sigstore/gitsign#environment-variables).

### Has access to `jdoe@example.com` Google Account, but official flow requires Github SSO (or vice-versa)

With Google credentials for `jdoe@example.com` (given that `example.com` is a Google-managed email domain),
the adversary can create a valid `SigningCertificate` (with correct email, ConnectorID and SigStore's signature),
and `gitsign verify` will rightfully verify the signature.

In this Github Action, if the expected ConnectorID is not Google (e.g the organization's flow strictly requires Github SSO
for commit signing), setting `connector-ids: "https://accounts.google.com"` will fail to verify any signature that does not
have `https://accounts.google.com` in the PKCS#7 field `1.3.6.1.4.1.57264.1.1` (https://github.com/sigstore/gitsign#inspecting-the-git-commit-signature).

### Fully compromises the identity of `jdoe@example.com` and pushes an amended commit

With full access to `jdoe@example.com` identity (through the trusted IdP), the adversary can create perfectly signed commits
(that rightfully pass `gitsign verify`).

Given that adding NEW commits to the deployable code (pushing/merging to deployable branches) would require peer-review, amending a deployable branch would be a plausible way to inject code.

If this Github Action is used, setting `check-signing-date: true` will additionally try to verify that all commits are signed in their
`SigningCertificate` Validity date window, thous failing to verify the amended commits, as they are signed with a Certificate issued
after the original commits were made (created by the adversary's through `jdoe@example.com` stolen identity).

Re-dating commits and resigning to bypass this check is also plausible (e.g `git commit -S --amend --date="..."`), and cannot be thoroughly
prevented without verifying commits in a non-atomic way (verification requires information from previous commits).

Yet, apart from amending history to deployable branches being a highly destructive action (diverging commit histories of cloned repositories - disrupting `git pull`), it also creates a visual clue in Github and Gitlab UI (e.g annotations like `X days/months/years ago` next to changed files), making the action very detectable.
