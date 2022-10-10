# gitsign-action

This Github Action verifies [Sigstore `gitsign`](https://github.com/sigstore/gitsign) key-less commit signatures for a chain of commits.

## Verifications

The Github Action verifies that all commits between `HEAD` and the git ref specified in the `ref` input:

* Are *signed* by the `gitsign` tool
* The signer's name (the `SigngingCertificate`'s `X509v3 SAN:email`) is the same with the git commit's author email
* If the `email-domains` input is set - the signer's email domain is in the `email-domains` list

## How it works

The Github Action loops through the commits between `ref` input and `HEAD`.
If a non-verifiable commit is found, the Github Action fails and reports which commit failed to verify.

```
[commit*N] {branch1} (checked) <-- Action runs in this commit
  |
  v
[commit*N-1] (checked)
  |
  v
[...] (checked)
  |
  v
[commit*1] (checked)
  |
  v
[commit] {ref=origin/master} 
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
      uses: skroutz-internal/gitsign-action@master
      with:
      	version: '0.3.1'	# default '0.3.1'
        ref: origin/master	# default 'origin/master'
        email-domains: "gmail.com users.noreply.github.com" # default ''

```

## Enable `Gitsign` for a repository

Gitsign configuration can be found in [repository's `README.md`](https://github.com/sigstore/gitsign#configuration)
