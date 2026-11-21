# Securing your tailnet

Tailscale is what lets your laptop, phone and the home server reach each other: every parajynx machine
runs it, sync and DeviceLink use nothing else, and the homelab's pages open only through it. So whoever
can get into your tailnet can get to everything. These steps keep that to you, in order of how much they
matter.

## 1. Lock the front door: your sign-in

Your tailnet is exactly as safe as the account you sign in to Tailscale with.

- Sign in with an account that has **two-factor authentication** on (a passkey or an authenticator app,
  not SMS). Turn it on at the provider (Google, GitHub, Microsoft…) before anything else.
- Use your personal account, not a school or work one: the school can lock or delete it.

## 2. Approve every new device yourself

Admin page → **Settings → Device management → Device approval → Manually approve new devices**. A stolen
password then still can't add a machine to your tailnet without you clicking Approve.

## 3. Replace "everyone reaches everything" with a policy

A new tailnet lets every device reach every port of every other device. Admin page → **Access controls**,
replace the file with this (edit the subnet to yours if you use `homelab.lanSubnet`):

```jsonc
{
  // Who may put the "homelab" label on a machine: you.
  "tagOwners": { "tag:homelab": ["autogroup:admin"] },

  "acls": [
    // Your own devices reach each other (sync, DeviceLink, screen sharing).
    { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self:*"] },
    // You reach every service on the home server.
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:homelab:*"] },
    // The server may reach your devices only to sync (22000) and pair (58846).
    { "action": "accept", "src": ["tag:homelab"], "dst": ["autogroup:member:22000,58846"] },
    // Friends you share the server with: Minecraft only, nothing else.
    { "action": "accept", "src": ["autogroup:shared"], "dst": ["tag:homelab:25565-25575"] },
  ],

  // The server's bridges are approved by this file, not by hand each time.
  "autoApprovers": {
    "routes":   { "192.168.1.0/24": ["tag:homelab"] },
    "exitNode": ["tag:homelab"],
  },
}
```

Then label the server as the homelab (run on the server, once):

```bash
sudo tailscale up --advertise-tags=tag:homelab --accept-dns=false
```

What a tag changes: the server now belongs to the tailnet rather than to your account, and its key no
longer expires, so a 24/7 machine never drops off. Your laptops and phone keep normal keys.

## 4. Keep key expiry on for everything you carry

Laptops and phones keep the default expiry (re-sign-in every few months). If one is lost or stolen:
Admin page → **Machines** → that device → **Remove**. It's out at once, everywhere.

## 5. Share the server, not the tailnet

To let a friend join your Minecraft server, use **Machines → the server → Share** (they get that one
machine, and the policy above lets them reach only the game ports). Don't invite friends as members of
your tailnet: members are "you" in the policy.

## 6. Leave the public doors shut

- **Funnel** (publishing a service to the whole internet) stays off. Nothing in parajynx needs it.
- **Serve** is fine: it only shares inside the tailnet.
- Approve **exit node** and **subnet routes** only for the server (the policy does that for you).
- **Tailscale SSH** isn't needed: the server has no SSH open, you use it from its own screen.

## 7. Optional, for the careful: Tailnet Lock

**Settings → Tailnet Lock.** New devices must then also be signed by one of your own trusted devices,
so not even Tailscale's coordination servers could add one. Read its page first: you get recovery
codes, and losing all your signing devices *and* those codes locks you out of adding machines.

## 8. Every month or so

Admin page → **Machines**: remove anything you don't recognise or don't use any more.
**Logs → Configuration** shows who changed what.

## What parajynx does on its side

- Every service, sync, DeviceLink pairing and screen sharing listen only on the Tailscale interface.
  The home network sees Pi-hole's DNS port and the Minecraft game ports (when Minecraft is on), and
  nothing else.
- Syncthing uses no public discovery or relay servers: your files only ever travel inside the tailnet.
- Screen sharing (`devlink screen`) accepts exactly one address, the linked machine's Tailscale IP,
  plus a fresh password each time.
