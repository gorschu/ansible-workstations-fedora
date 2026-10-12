# AirVPN connections

The networking role installs the same four manually activated AirVPN profiles on
every workstation:

| NetworkManager name | Interface | Endpoint |
| --- | --- | --- |
| AirVPN — America | wg-airvpn-am | america3.vpn.airdns.org:1637 |
| AirVPN — Europe | wg-airvpn-eu | europe3.vpn.airdns.org:1637 |
| AirVPN — Germany | wg-airvpn-de | de3.vpn.airdns.org:1637 |
| AirVPN — Netherlands | wg-airvpn-nl | nl3.vpn.airdns.org:1637 |

Select a profile in the desktop network controls, or use:

```sh
nmcli connection up 'AirVPN — Germany'
nmcli connection down 'AirVPN — Germany'
```

The profiles route IPv4 and IPv6 through AirVPN and use its supplied DNS servers.
The configured LAN subnets stay directly reachable. With systemd-resolved, existing
LAN DNS search domains remain available while general DNS queries use AirVPN.
MTU 1320 and the 15-second keepalive match the downloaded profiles. Each interface
has its own fixed listen port, following the existing NetworkManager workaround.

Shared credentials and tunnel addresses live once in encrypted `vault.yml`:

```yaml
vault_networking_airvpn:
  private_key: <WireGuard private key>
  preshared_key: <WireGuard preshared key>
  peer_public_key: <AirVPN peer public key>
  address_ipv4: <IPv4 address/prefix>
  address_ipv6: <IPv6 address/prefix>
  dns_ipv4: [<IPv4 DNS server>]
  dns_ipv6: [<IPv6 DNS server>]
```

Profile names and endpoints are defined in `networking_airvpn_profiles`.
`networking_airvpn_state: absent` skips installation; the vault-free test VM uses
this setting. Run the playbook with `--tags airvpn` to deploy only these profiles
and reload NetworkManager's connection definitions.
