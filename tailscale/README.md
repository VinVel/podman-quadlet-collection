# Headscale and Headplane with Pocket ID

This rootless Podman pod runs Headscale and Headplane. Headscale's control
server uses `headscale.example.com`; Headplane's admin UI uses
`heaplane.example.com/admin/`. The HTTP ports bind only to `127.0.0.1` for
host NGINX. Headscale receives public UDP/3478 directly through Podman's
rootless `pasta` forwarding and firewalld. It uses its own embedded DERP/STUN
relay, not the Tailscale public DERP map. Both YAML files contain only ordinary
settings and paths to **Podman secrets**. No rendered secret-bearing config
file is needed.

## Before installing

Create **one confidential Pocket ID OIDC client** with PKCE S256 enabled. Add
both callback URLs:

```text
https://headscale.example.com/oidc/callback
https://heaplane.example.com/admin/oidc/callback
```

Restrict this client to your intended Pocket ID group. Headscale also checks
that group via `oidc.allowed_groups`. Using the same client for Headplane lets
it match a Headplane sign-in to the corresponding Headscale user.

From the repository root, replace the example Headplane UI hostname in the
README, Headplane config, and NGINX example before installing:

```sh
headplane_domain='ui.yourdomain.tld'
sed -i "s/heaplane\.example\.com/$headplane_domain/g" \
  tailscale/README.md tailscale/headplane.yaml tailscale/nginx.conf.example
```

Set the Headscale and Pocket ID hostnames separately; they serve different
endpoints. Run the installation commands below from the `tailscale` directory.

## Install and create secrets

```sh
tailscale podman quadlet install --application=tailscale \
  "$PWD/tailscale.quadlets" "$PWD/headscale.yaml" "$PWD/headplane.yaml"

tailscale systemctl --user enable --now podman.socket

systemd-ask-password -n | tailscale podman secret create headplane_oidc_client_secret -

# The 32-character session key is generated directly into Podman's secret store.
create-password | tailscale podman secret create headplane_cookie_secret -

# Headscale emits a correctly formatted private key. Each is generated once.
tailscale podman run --rm --read-only \
  docker.io/headscale/headscale:0.29 generate private-key \
  | tailscale podman secret create headscale_noise_private_key -
tailscale podman run --rm --read-only \
  docker.io/headscale/headscale:0.29 generate private-key \
  | tailscale podman secret create headscale_derp_private_key -

tailscale systemctl --user daemon-reload
tailscale systemctl --user start tailscale-pod.service

# Headscale must be running before it can issue Headplane's API key.
tailscale podman exec headscale headscale apikeys create --expiration 365d \
  | tailscale podman secret create headplane_headscale_api_key -
tailscale systemctl --user start headplane.service
```

Keep secure backups of the two private keys and the data bind mounts; Headscale's identity depends on
its Noise key. The Headplane API key expires after one year in this example.
Generate a replacement, replace that Podman secret, and recreate Headplane
before it expires. Recreating a Podman secret does not update a running
container's mounted copy.

Headplane can edit **Settings and DNS**. It writes the shared Headscale config
and uses the built-in rootless Podman API socket to restart the labeled
Headscale container. Headscale mounts the config read-only. The config contains
paths to Podman secrets, not their values. UI edits change the installed YAML
at `%h/.config/containers/systemd/headplane/headscale.yaml`.

The Podman API socket gives Headplane full control of this rootless user's
Podman containers. Podman's documented socket access requires disabling
SELinux label separation for Headplane; Headscale remains confined. Headplane's
mounts do not request relabeling. Headscale applies `:z` to the shared config
and `:Z` to its private data. Mounting the socket
read-only does not make the API read-only. Use a dedicated service user if this
access should be limited to the Headscale and Headplane stack.

Headscale needs one `trusted_proxies` entry to use NGINX's real client IP in
its logs. The pod pins pasta's host-loopback source address to `192.0.2.1`;
this is a virtual address inside the pod, not a public listener. Headscale
trusts exactly `192.0.2.1/32`. NGINX replaces any inbound client-IP
headers with `$remote_addr` before forwarding. This trust entry identifies the
proxy connection as Headscale sees it; the firewall's public-port rules do not
tell Headscale whether an HTTP header came from NGINX.

## NGINX and direct STUN

Merge the `http` block from `nginx.conf.example` into your host NGINX config.
Point DNS for both hostnames to this host, set certificates for both HTTPS
hosts, run `sudo nginx -t`, then reload NGINX. The Headscale vhost permits
cross-origin API requests from the Headplane UI vhost. Headscale serves STUN
directly on public UDP/3478; NGINX does not handle that port. Keep TCP/443
open for HTTPS and add UDP/3478 to the host's public firewalld zone (shown here
as `FedoraServer`):

```sh
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=3478/udp
sudo firewall-cmd --reload
```

Rootless [Podman pasta forwarding](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
preserves the original client IP; verify from an external client that STUN
reports the client's public IP **and source port**. The example publishes IPv4
UDP only, so advertise an IPv4 address for the Headscale hostname.

On SELinux hosts, host NGINX may also need
`sudo setsebool -P httpd_can_network_connect 1` to reach the localhost TCP
backends. Headscale's private data bind mount is relabeled with `:Z`.

## Check the services

```sh
curl -f https://headscale.example.com/health
curl -sS -o /dev/null -w '%{http_code}\n' https://heaplane.example.com/admin/
tailscale up --login-server https://headscale.example.com
tailscale debug derp-map
tailscale debug derp headscale
journalctl --user -u headscale.service -u headplane.service
```

Open `https://heaplane.example.com/admin/` and sign in with Pocket ID. The
first Headplane user becomes its owner, so perform that first sign-in using the
intended administrator account. Back up both `%h/headplane-data`
directories along with the Podman secrets before upgrades.

