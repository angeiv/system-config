:title: Signing System

.. _signing:

Signing System
##############

Our standard signing automation leverages an OpenPGP signing subkey,
encrypted as a Zuul secret, to create detached signatures for
release artifacts (tarballs, wheels, et cetera) and to sign and push
Git tags as part of our managed release automation. The master key
corresponding to this subkey is replaced near the start of each new
development cycle and set to expire soon after the cycle is
scheduled to conclude (with enough overlap to allow for graceful
replacement).


At a Glance
===========

:Secrets:
  * `gpg_key
    <https://git.openstack.org/cgit/openstack-infra/project-config/tree/zuul.d/secrets.yaml>`_
:Roles:
  * `add-gpgkey
    <https://docs.openstack.org/infra/zuul-jobs/roles.html#role-add-gpgkey>`_
  * `sign-artifacts
    <https://docs.openstack.org/infra/zuul-jobs/roles.html#role-sign-artifacts>`_


Key Management Overview
=======================

The signing system is implemented as a set of Zuul v3 jobs; these
utilize the signing subkey via an encrypted Zuul secret imported
into a job's ``~/.gnupg/secring.gpg`` at runtime. It's used by jobs
to create detached signatures of release artifacts and to sign Git
tags under release management automation.


Storage
-------

While the signing subkey is installed unencrypted on some job nodes,
so that it can be used unattended by job automation, the
corresponding master key is kept symmetrically encrypted in the root
home directory of the Infra systems management bastion instead. At
the time of key creation a revocation certificate is also generated,
for which Infra root sysadmins are encouraged to retrieve and keep
local copies in case control over or access to the original master
key is lost. In the future, the master key and revocation
certificate may be distributed across our root team rather than kept
in one place (for example using Shamir's secret sharing scheme
similar to what `the Debian Project does for its archive keys
<https://ftp-master.debian.org/keys.html>`).


Rotation
--------

The master key is rotated at the start of each development cycle
(usually shortly after cycle-trailing deliverables are released),
signed by a majority of Infra root sysadmins before being put into
service, and has an expiration date set for a month after the end of
the targeted development cycle. The newly-created key gets signed by
the old, and this signature pushed to the public keyserver network.
New key fingerprints are also submitted to the openstack/releases
repository, for publication on the releases.openstack.org Web site.


Revocation
----------

Under normal circumstances, keys should be allowed to expire
gracefully. If the key is compromised but still accessible, a
revocation certificate can be generated and published to the key
network at that time. If access to the private key is lost
completely, the revocation certificate generated at key creation
time should be used as a last resort.


Key Management Process
======================

Configuration
-------------

This is the content of the ``/root/signing.gnupg/gpg.conf`` file on
our management bastion host::

    # A basic gpg.conf using secure keyserver transport and some more
    # verbose display options. This configuration assumes you have
    # installed both the gnupg and gnupg-curl packages. Set your umask
    # to 077, create a /root/signing.gnupg directory and place this
    # configuration file in it.
    #
    # Retrieve and validate the HKPS key for the SKS keyservers this way:
    #
    #     wget -P ~/signing.gnupg/ \
    #         https://sks-keyservers.net/sks-keyservers.netCA.pem{,.asc}
    #     gpg --homedir signing.gnupg --recv-key \
    #         0x94CBAFDD30345109561835AA0B7F8B60E3EDFAE3
    #     gpg --homedir signing.gnupg --verify \
    #         ~/signing.gnupg/sks-keyservers.netCA.pem{.asc,}
    #
    # You'll need to list them in the accompanying dirmngr.conf file.

    # Receive, send and search for keys in the SKS keyservers pool using
    # HKPS (OpenPGP HTTP Keyserver Protocol via TLS/SSL).
    keyserver hkps://hkps.pool.sks-keyservers.net

    # Ignore keyserver URLs specified in retrieved/refreshed keys
    # so they don't direct you to update from non-HKPS sources.
    keyserver-options no-honor-keyserver-url

    # Display key IDs in a more accurate 16-digit hexidecimal format
    # and add 0x at the beginning for clarity.
    keyid-format 0xlong

    # Display the calculated validity of user IDs when listing keys or
    # showing signatures.
    list-options show-uid-validity
    verify-options show-uid-validity

And this is the content of the ``/root/signing.gnupg/dirmngr.conf`` file on
our management bastion host::

    # Set the path to the public certificate for the
    # sks-keyservers.net CA used to verify connections to servers in
    # the accompanying gpg.conf file.
    hkp-cacert /root/signing.gnupg/sks-keyservers.netCA.pem


Generation
----------

Key generation should happen reasonably far in advance of expiration
of the old key (at least a month), so as to provide ample time for a
majority of our root sysadmins to attest to the key and provide
warning to the rest of the community of the upcoming transition. Of
course, if this is being done to replace a revoked key, this
timeline should be accelerated as much as possible to provide
continuity of service so use your best judgement on a balance of
sufficient attestation and warning (same-day turnaround is
preferred).

Make sure we start with a restrictive umask so that files and
directories we write from this point forward are only accessible by
the root user:

.. code-block:: shell-session

    root@bridge:~# umask 077

Now create a master key for the coming development cycle, taking
mostly the GnuPG recommended default values. Set a validity period
sufficient to last through the release process at the conclusion of
the cycle. Use a sufficiently long, randomly-generated passphrase
string (it's fine to reuse the one stored in our passwords list for
earlier keys unless we know it to have been compromised):

.. code-block:: shell-session

    root@bridge:~# gpg --homedir signing.gnupg --full-generate-key
    gpg (GnuPG) 2.2.4; Copyright (C) 2017 Free Software Foundation, Inc.
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.

    Please select what kind of key you want:
       (1) RSA and RSA (default)
       (2) DSA and Elgamal
       (3) DSA (sign only)
       (4) RSA (sign only)
    Your selection?
    RSA keys may be between 1024 and 4096 bits long.
    What keysize do you want? (2048)
    Requested keysize is 2048 bits
    Please specify how long the key should be valid.
             0 = key does not expire
          <n>  = key expires in n days
          <n>w = key expires in n weeks
          <n>m = key expires in n months
          <n>y = key expires in n years
    Key is valid for? (0) 9m
    Key expires at Thu 02 Feb 2017 08:41:39 PM UTC
    Is this correct? (y/N) y

    You need a user ID to identify your key; the software constructs the user ID
    from the Real Name, Comment and Email Address in this form:
        "Heinrich Heine (Der Dichter) <heinrichh@duesseldorf.de>"

    Real name: OpenStack Infra
    Email address: infra-root@openstack.org
    Comment: Some Cycle
    You selected this USER-ID:
        "OpenStack Infra (Some Cycle) <infra-root@openstack.org>"

    Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit? o
    You need a Passphrase to protect your secret key.

    Enter passphrase: ********************************
    Repeat passphrase: ********************************

    We need to generate a lot of random bytes. It is a good idea to perform
    some other action (type on the keyboard, move the mouse, utilize the
    disks) during the prime generation; this gives the random number
    generator a better chance to gain enough entropy.
    .+++++
    ......+++++
    We need to generate a lot of random bytes. It is a good idea to perform
    some other action (type on the keyboard, move the mouse, utilize the
    disks) during the prime generation; this gives the random number
    generator a better chance to gain enough entropy.
    .+++++
    +++++
    gpg: key 0x120D3C23C6D5584D marked as ultimately trusted
    public and secret key created and signed.

    gpg: checking the trustdb
    gpg: 3 marginal(s) needed, 1 complete(s) needed, PGP trust model
    gpg: depth: 0  valid:   1  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 1u
    gpg: next trustdb check due at 2017-02-02
    pub   rsa3072/0x120D3C23C6D5584D 2016-07-07 [expires: 2017-02-02]
          Key fingerprint = 7222 E5A0 5730 B767 0F93  035A 120D 3C23 C6D5 584D
    uid                 [ultimate] OpenStack Infra (Some Cycle) <infra-root@openstack.org>
    sub   rsa3072/0x1F215B56867C5D9A 2016-07-07 [expires: 2017-02-02]

Create a revocation certificate for the master key, for use in the
case extreme case that this master key itself becomes inaccessible,
for example because the decryption passphrase is lost (under any
other circumstances, a revocation certificate with a more detailed
description can be generated using the master key on an as-needed
basis). Replace ``some`` in the output filename with the lower-cased
cycle name:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir signing.gnupg --output \
    > signing.gnupg/some.revoke.asc --gen-revoke 0x120D3C23C6D5584D
    sec  rsa3072/0x120D3C23C6D5584D 2016-07-07 OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    Create a revocation certificate for this key? (y/N) y
    Please select the reason for the revocation:
      0 = No reason specified
      1 = Key has been compromised
      2 = Key is superseded
      3 = Key is no longer used
      Q = Cancel
    (Probably you want to select 1 here)
    Your decision? 1
    Enter an optional description; end it with an empty line:
    > This revocation is to be used in the event the key cannot be recovered.
    >
    Reason for revocation: Key has been compromised
    This revocation is to be used in the event the key cannot be recovered.
    Is this okay? (y/N) y

    You need a passphrase to unlock the secret key for
    user: "OpenStack Infra (Some Cycle) <infra-root@openstack.org>"
    2048-bit RSA key, ID 0x120D3C23C6D5584D, created 2016-07-07

    Enter passphrase: ********************************

    ASCII armored output forced.
    Revocation certificate created.

    Please move it to a medium which you can hide away; if Mallory gets
    access to this certificate he can use it to make your key unusable.
    It is smart to print this certificate and store it away, just in case
    your media become unreadable.  But have some caution:  The print system of
    your machine might store the data and make it available to others!

Use the interactive key editor to add a subkey constrained to
signing purposes only. It does not need an expiration since it will
be valid only for as long as its associated master key is valid:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir signing.gnupg --edit-key 0x120D3C23C6D5584D
    gpg (GnuPG) 2.2.4; Copyright (C) 2017 Free Software Foundation, Inc.
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.

    Secret key is available.

    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage: SC
                                   trust: ultimate      validity: ultimate
    sub  rsa3072/0x1F215B56867C5D9A  created: 2016-07-07  expires: 2017-02-02  usage: E
    [ultimate] (1). OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    gpg> addkey
    Please select what kind of key you want:
       (3) DSA (sign only)
       (4) RSA (sign only)
       (5) Elgamal (encrypt only)
       (6) RSA (encrypt only)
    Your selection? 4
    RSA keys may be between 1024 and 4096 bits long.
    What keysize do you want? (2048)
    Requested keysize is 2048 bits
    Please specify how long the key should be valid.
             0 = key does not expire
          <n>  = key expires in n days
          <n>w = key expires in n weeks
          <n>m = key expires in n months
          <n>y = key expires in n years
    Key is valid for? (0)
    Key does not expire at all
    Is this correct? (y/N) y
    Really create? (y/N) y
    Key is protected.

    You need a passphrase to unlock the secret key for
    user: "OpenStack Infra (Some Cycle) <infra-root@openstack.org>"
    2048-bit RSA key, ID 0x120D3C23C6D5584D, created 2016-07-07

    Enter passphrase: ********************************

    We need to generate a lot of random bytes. It is a good idea to perform
    some other action (type on the keyboard, move the mouse, utilize the
    disks) during the prime generation; this gives the random number
    generator a better chance to gain enough entropy.
    +++++
    ........+++++

    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage: SC
                               trust: ultimate      validity: ultimate
    sub  rsa3072/0x1F215B56867C5D9A  created: 2016-07-07  expires: 2017-02-02  usage: E
    sub  rsa3072/0xC0224DB5F541FB68  created: 2016-07-07  expires: never       usage: S
    [ultimate] (1). OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    gpg> save

Next, sign the new master key with the key from the previous cycle
(specified with the ``--default-key`` option). This proves that the
new key was created by a party with access to its predecessor, so
provides some added assurance of its validity:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir signing.gnupg --default-key 0x70CA2E45DF30B1B8 --sign-key 0x120D3C23C6D5584D

    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage:SC
                                   trust: ultimate      validity: ultimate
    sub  rsa3072/0x1F215B56867C5D9A  created: 2016-07-07  expires: 2017-02-02  usage:E
    sub  rsa3072/0xC0224DB5F541FB68  created: 2016-07-07  expires: never       usage:S
    [ultimate] (1). OpenStack Infra (Pike Cycle) <infra-root@openstack.org>


    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage:SC
                                   trust: ultimate      validity: ultimate
     Primary key fingerprint: 120D 3C23 C6D5 584D 6FC2  4646 64DB B05A CC5E 7C28

         OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    This key is due to expire on 2017-02-02.
    Are you sure that you want to sign this key with your
    key "OpenStack Infra (Previous Cycle) <infra-root@openstack.org>" (0x70CA2E45DF30B1B8)

    Really sign? (y/N) y

    You need a passphrase to unlock the secret key for
    user: "OpenStack Infra (Previous Cycle) <infra-root@openstack.org>"
    2048-bit RSA key, ID 0x70CA2E45DF30B1B8, created 2016-11-03

    Enter passphrase: ********************************

Now send the master key to the keyserver network. The subkeys are
all submitted along with it, so do not need to be specified
separately:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir signing.gnupg --send-keys 0x120D3C23C6D5584D
    sending key 0x120D3C23C6D5584D to hkps server hkps.pool.sks-keyservers.net

The rest of this process shouldn't happen until we're ready for the
signing system to transition to our new key. In a typical,
non-emergency rotation this should not happen until release
activities for the previous cycle have concluded so that we don't
inadvertently sign their artifacts with the new key.

Create a new GnuPG keychain by exporting a copy of just the signing
subkey to a file and then importing that (and only that) in a new
GnuPG directory:

.. code-block:: shell-session

    root@bridge:~# umask 077
    root@bridge:~# mkdir temporary.gnupg
    root@bridge:~# gpg --homedir signing.gnupg \
    > --output temporary.gnupg/secret-subkeys
    > --export-secret-subkeys 0xC0224DB5F541FB68\!
    root@bridge:~# gpg --homedir temporary.gnupg \
    > --import temporary.gnupg/secret-subkeys
    gpg: keyring `temporary.gnupg/secring.gpg' created
    gpg: keyring `temporary.gnupg/pubring.gpg' created
    gpg: key C6D5584D: secret key imported
    gpg: temporary.gnupg/trustdb.gpg: trustdb created
    gpg: key C6D5584D: public key "OpenStack Infra (Some Cycle) <infra-root@openstack.org>" imported
    gpg: Total number processed: 1
    gpg:               imported: 1  (RSA: 1)
    gpg:       secret keys read: 1
    gpg:   secret keys imported: 1

Check that the exported version does not contain a usable primary
secret key by listing all secret keys and looking for a ``sec#`` in
front of it instead of just ``sec``:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir temporary.gnupg --list-secret-keys

    /root/temporary.gnupg/pubring.kbx
    ---------------------------------
    sec#  rsa3072 2016-07-07 [SC] [expires: 2017-02-02]
          120D3C23C6D5584D
    uid           [unknown] OpenStack Infra (Some Cycle) <infra-root@openstack.org>
    ssb   rsa3072 2016-07-07 [S]

So that our CI jobs will be able to make use of this subkey without
interactively supplying a passphrase, the old passphrase (exported
from the master key) must be reset to an empty string in the new
temporary copy. Here we override the default pinentry mode to
loopback as a workaround for other pinentry frontends refusing to
accept an empty passphrase (unfortunately the prompting and feedback
from the loopback pinentry leaves something to be desired). This is
again done using an interactive key editor session:

.. code-block:: shell-session

    root@bridge:~# gpg --homedir temporary.gnupg --pinentry-mode loopback \
    > --edit-key 0xC0224DB5F541FB68
    gpg (GnuPG) 2.2.4; Copyright (C) 2017 Free Software Foundation, Inc.
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.

    Secret subkeys are available.

    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage: SC
                     trust: unknown       validity: unknown
    sub  rsa3072/0xC0224DB5F541FB68  created: 2016-07-07  expires: never       usage: S
    [ unknown] (1). OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    gpg> passwd
    gpg: key 120D3C23C6D5584D/120D3C23C6D5584D: error changing passphrase: No secret key
    Enter passphrase: ********************************
    Enter passphrase:

    gpg> save
    Key not changed so no update needed.

Test the subkey can be used without a passphrase::

  root@bridge:~# echo foo | gpg --homedir temporary.gnupg --sign --armor
  -----BEGIN PGP MESSAGE-----

  owEB0QEu/pANAwAKARpUEUgFTp44AcsKYgBbid4PZm9vCokBswQAAQoAHRYhBB5+
  uy3Npgy9sH8nfBpUEUgFTp44BQJbid4PAAoJEBpUEUgFTp4486YMAIQ8zfP5ZBTq
  7+d6ZAO25HeYCXwqU7qqNRazrceyfBBcES6+TvOtbpNPxpCzAhT2RhkIJZMJaetF
  /RObIXn5/nHdXRsEKgTIxoyPMfxo5M8zbLqnm7NEsFzUjK2lojBPxBQs/SxiD9Qy
  5Hvv7sAtgNV11dzzoTtyIfOXU9dUjuEnfgboc7z410ctflgI8USRiaYaCJbdj1J/
  iGlplq/jTNMnIB3N15M5M5U9GfFO05MVyoPz0qi3t9gWP8hkOnvOSakG25NVGB4l
  zUbMR1oK8pmLJ33fcw/8/TejjeI2FVJh9jSVE8v4O77Iiir8XcIC+PwT2MK/HIda
  SR43vh1iK66BbmlsONWxII74fIPEDHDeCqVnkzxdhleDf7DOd9HhYmI8WNOKtTIU
  7hcy6cYqHBjEgVr5oViNiveiwGsKlOUhh8x1eYDIxEEoGQEHDJDKq9YOMMjRdsO8
  fOw0TD/1r8Lmi8QLkCfGvFdrSY6EoCHqCMx3+JmGUD+iFGp2rCOucw==
  =LxND
  -----END PGP MESSAGE-----

This leaves us with a temporary keyring containing only an unencrypted
copy of the signing subkey. Export this keyring so that we can add it
as a secret to Zuul for use by release jobs.

.. code-block:: shell-session

    root@bridge:~# gpg --homedir temporary.gnupg \
    > --output temporary.gnupg/for-zuul --armor \
    > --export-secret-subkeys 0xC0224DB5F541FB68\!
    root@bridge:~# wget https://git.openstack.org/cgit/openstack-infra/zuul/plain/tools/encrypt_secret.py
    root@bridge:~# python3 encrypt_secret.py --tenant openstack \
    > --infile temporary.gnupg/for-zuul --outfile temporary.gnupg/zuul.yaml \
    > https://zuul.openstack.org openstack-infra/project-config
    writing RSA key
    Public key length: 4096 bits (512 bytes)
    Max plaintext length per chunk: 470 bytes
    Input plaintext length: 4818 bytes
    Number of chunks: 11

Copy ``temporary.gnupg/zuul.yaml`` to your workstation and make a
commit to ``zuul.d/secrets.yaml`` file in the
``openstack/project-config`` repo to update the ``gpg_key`` secret
with its contents.  Be sure to replace ``<name>`` and
``<fieldname>`` as appropriate.

Safely clean up, doing your best to securely remove the temporary
copy of the unencrypted signing subkey and any associated files:

.. code-block:: shell-session

    root@bridge:~# find temporary.gnupg/ -type f -exec shred {} \;
    root@bridge:~# rm -rf temporary.gnupg encrypt_secret.py

To document this transition, export a minimal text version of the
public master key:

.. code-block:: shell-session

    root@bridge:~# ( gpg --fingerprint \
    > 0x120d3c23c6d5584d6fc2464664dbb05acc5e7c28
    > gpg --armor --export-options export-clean,export-minimal \
    > --export 0x120d3c23c6d5584d6fc2464664dbb05acc5e7c28 ) > \
    > 0x120d3c23c6d5584d6fc2464664dbb05acc5e7c28.txt

Add the file to a change for the ``openstack/releases`` repo placing
it in the ``doc/source/static`` directory, and then link it similarly
to other exported public keys are linked in the `Cryptographic
Signatures
<https://releases.openstack.org/#cryptographic-signatures>` section
of ``doc/source/index.rst`` (noting the appropriate end date for use
of the prior key as the start date for the new one).


Attestation
-----------

We need a majority (if not all) of our current root sysadmins to
verify and attest to the authenticity of our artifact signing key,
because it represents a system maintained by our team rather than
representing some particular individual and so anyone else attesting
to this key can really only do so transitively through us. This
should be done soon after a new key is minted (preferably the same
week) so that others in the community who wish to extend the web of
trust around the key based on our attestations (for example, release
managers or team leads) have an opportunity to do so before it's put
into production.

Start by logging into the management bastion and examining the
fingerprint of the key as it exists on disk:

.. code-block:: shell-session

    me@bridge:~$ sudo gpg --homedir /root/signing.gnupg --fingerprint \
    > --list-keys "OpenStack Infra (Some Cycle)"
    pub   rsa3072/0x120D3C23C6D5584D 2016-07-07 [expires: 2017-02-02]
          Key fingerprint = 120D 3C23 C6D5 584D 6FC2  4646 64DB B05A CC5E 7C28
    uid                 [ultimate] OpenStack Infra (Some Cycle) <infra-root@openstack.org>
    sub   rsa3072/0x1F215B56867C5D9A 2016-07-07 [expires: 2017-02-02]
    sub   rsa3072/0xC0224DB5F541FB68 2016-07-07

Now on your own system where your OpenPGP key resides, retrieve the
key, compare the fingerprint from above, and if they match, sign it
and push the signature back to the keyserver network:

.. code-block:: shell-session

    me@home:~$ gpg2 --recv-keys 0x120D3C23C6D5584D
    gpg: requesting key 0x120D3C23C6D5584D from hkps server hkps.pool.sks-keyservers.net
    gpg: key 0x120D3C23C6D5584D: public key "OpenStack Infra (Some Cycle) <infra-root@openstack.org>" imported
    gpg: 3 marginal(s) needed, 1 complete(s) needed, classic trust model
    gpg: depth: 0  valid:   3  signed:  31  trust: 0-, 0q, 0n, 0m, 0f, 3u
    gpg: depth: 1  valid:  31  signed:  46  trust: 30-, 0q, 0n, 0m, 1f, 0u
    gpg: next trustdb check due at 2016-11-30
    gpg: Total number processed: 1
    gpg:               imported: 1  (RSA: 1)
    me@home:~$ gpg2 --fingerprint 0x120D3C23C6D5584D
    pub   rsa3072/0x120D3C23C6D5584D 2016-07-07 [expires: 2017-02-02]
          Key fingerprint = 120D 3C23 C6D5 584D 6FC2  4646 64DB B05A CC5E 7C28
    uid                 [  full  ] OpenStack Infra (Some Cycle) <infra-root@openstack.org>
    sub   rsa3072/0x1F215B56867C5D9A 2016-07-07 [expires: 2017-02-02]
    sub   rsa3072/0xC0224DB5F541FB68 2016-07-07
    me@home:~$ gpg2 --sign-key 0x120D3C23C6D5584D

    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage: SC
                                   trust: unknown       validity: full
    sub  rsa3072/0x1F215B56867C5D9A  created: 2016-07-07  expires: 2017-02-02  usage: E
    sub  rsa3072/0xC0224DB5F541FB68  created: 2016-07-07  expires: never       usage: S
    [  full  ] (1). OpenStack Infra (Some Cycle) <infra-root@openstack.org>


    pub  rsa3072/0x120D3C23C6D5584D  created: 2016-07-07  expires: 2017-02-02  usage: SC
                                   trust: unknown       validity: full
     Primary key fingerprint: 120D 3C23 C6D5 584D 6FC2  4646 64DB B05A CC5E 7C28

         OpenStack Infra (Some Cycle) <infra-root@openstack.org>

    This key is due to expire on 2017-02-02.
    Are you sure that you want to sign this key with your
    key "My Name <me@example.org>" (0xAB54A98CEB1F0AD2)

    Really sign? (y/N) y

       +-----------------------------------------------------------------------+
       | Please enter the passphrase to unlock the secret key for the OpenPGP  |
       | certificate:                                                          |
       | "My Name <me@example.org>"                                            |
       | 2048-bit RSA key, ID 0xAB54A98CEB1F0AD2,                              |
       | created 2008-09-10.                                                   |
       |                                                                       |
       |                                                                       |
       | Passphrase **********************____________________________________ |
       |                                                                       |
       |          <OK>                                         <Cancel>        |
       +-----------------------------------------------------------------------+

    me@home:~$ gpg2 --send-keys 0x120D3C23C6D5584D
    gpg: sending key 0x120D3C23C6D5584D to hkps server hkps.pool.sks-keyservers.net

Also, please retrieve a copy of the
``/root/signing.gnupg/some.revoke.asc`` fallback revocation
certificate (``some`` to be replaced with the lower-cased release
name) from the management bastion and keep it stashed somewhere
secure, for emergency use in the (hopefully very unlikely) event
that our OpenPGP master private key is completely lost to us (for
example, if we lose the file containing its decryption passphrase
and all backups thereof).
