# OSINT / security toolkit. Authorised testing only.
{ pkgs, ... }:
let s = import ../settings.nix;
in {
  programs.wireshark = { enable = true; package = pkgs.wireshark; };
  users.users.${s.username}.extraGroups = [ "wireshark" ];
  # (SpiderFoot's pypdf2 insecure allowance lives in core.nix)

  environment.systemPackages = with pkgs; [
    nmap tcpdump termshark
    metasploit recon-ng theharvester osint-tools-cli spiderfoot sherlock
    aircrack-ng iw macchanger
    whois dnsutils
  ];
}
