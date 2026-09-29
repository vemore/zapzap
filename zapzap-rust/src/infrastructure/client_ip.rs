//! The key of a client for a per-client rate limit: its address behind the proxies.
//!
//! In production a request crosses two proxies before the backend: the Synology DSM
//! reverse proxy (TLS), then the `zapzap-proxy` nginx (`nginx/nginx.conf`). Each appends
//! the address it was connected from to `X-Forwarded-For` (`$proxy_add_x_forwarded_for`):
//! DSM the client's, nginx DSM's. So the client is the entry `TRUSTED_PROXY_HOPS` (2) from
//! the right; whatever stands left of it was sent by the client and is not trusted.
//! DSM appends only through a custom header on its zapzap rule (`.llmwiki/Deployment.md`).
//! nginx's `X-Real-IP` is DSM's address, the same for every client: not used.
//!
//! Once every trusted proxy appends (DSM needs its custom header), the key is never an
//! entry the client could have chosen: a header with fewer entries than the hop count (a
//! proxy did not append, so its leftmost entry may be the client's own), or an entry that
//! is not an IP address, falls back to the connection's peer. Without DSM's entry, a
//! client that sends `X-Forwarded-For: <forged>` reaches the backend as `[<forged>, DSM]`:
//! the count matches, and no hop count tells it from `[client, DSM]`. An
//! IPv6 address is keyed by its /64, the block one subscriber gets; an IPv4-mapped one by
//! its IPv4.

use std::net::{IpAddr, Ipv6Addr, SocketAddr};

use axum::http::HeaderMap;

/// The proxies in front of the backend in production: DSM, then nginx
pub const DEFAULT_TRUSTED_PROXY_HOPS: usize = 2;

/// `TRUSTED_PROXY_HOPS`: how many proxies append to `X-Forwarded-For` before the backend,
/// `DEFAULT_TRUSTED_PROXY_HOPS` when unset or not a number; `0` trusts no header
pub fn trusted_proxy_hops_from(value: Option<String>) -> usize {
    value
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(DEFAULT_TRUSTED_PROXY_HOPS)
}

/// The client's rate-limit key, and what the log line that checks the hop count needs
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientIp {
    /// `rate_limit_key` of the client's address, or `unknown`
    pub key: String,
    /// The entries `X-Forwarded-For` held (0 without the header)
    pub forwarded_entries: usize,
}

/// The key of `ip`: an IPv4 address whole; an IPv6 one by its /64 (`2001:db8:1:2::/64`),
/// since one subscriber gets a whole /64 and would otherwise hold 2^64 keys; an
/// IPv4-mapped IPv6 one (`::ffff:203.0.113.7`) as its IPv4
pub fn rate_limit_key(ip: IpAddr) -> String {
    match ip {
        IpAddr::V4(v4) => v4.to_string(),
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => v4.to_string(),
            None => {
                let [a, b, c, d, ..] = v6.segments();
                format!("{}/64", Ipv6Addr::new(a, b, c, d, 0, 0, 0, 0))
            }
        },
    }
}

/// The client's key: that of the `X-Forwarded-For` entry `hops` from the right when the
/// header holds at least `hops` entries and that entry is an IP address; else that of the
/// connection's peer (no header, `hops` 0, a proxy that did not append, an entry that is
/// not an address); else `unknown` (the API tests, which have no connection)
pub fn client_ip(headers: &HeaderMap, peer: Option<SocketAddr>, hops: usize) -> ClientIp {
    let entries: Vec<&str> = headers
        .get_all("x-forwarded-for")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .collect();
    let forwarded = if hops == 0 || entries.len() < hops {
        None
    } else {
        entries[entries.len() - hops].parse::<IpAddr>().ok()
    };
    let key = forwarded
        .or_else(|| peer.map(|p| p.ip()))
        .map(rate_limit_key)
        .unwrap_or_else(|| "unknown".to_string());
    ClientIp {
        key,
        forwarded_entries: entries.len(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn headers(xff: &[&str]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for v in xff {
            h.append("x-forwarded-for", v.parse().unwrap());
        }
        h
    }

    fn peer() -> Option<SocketAddr> {
        Some("172.18.0.5:41000".parse().unwrap())
    }

    fn key(ip: &str) -> String {
        rate_limit_key(ip.parse().unwrap())
    }

    #[test]
    fn behind_dsm_and_nginx_the_client_is_second_from_the_right() {
        let got = client_ip(&headers(&["203.0.113.7, 192.168.1.25"]), peer(), 2);
        assert_eq!(got.key, "203.0.113.7");
        assert_eq!(got.forwarded_entries, 2);
    }

    #[test]
    fn what_the_client_sent_itself_is_not_trusted() {
        // The client sent `X-Forwarded-For: 1.2.3.4`; DSM and nginx appended theirs
        let h = headers(&["1.2.3.4, 203.0.113.7, 192.168.1.25"]);
        let got = client_ip(&h, peer(), 2);
        assert_eq!(got.key, "203.0.113.7");
        assert_eq!(got.forwarded_entries, 3);
        // Several header lines read as one list
        let h = headers(&["1.2.3.4", "203.0.113.7, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).key, "203.0.113.7");
    }

    #[test]
    fn a_missing_hop_keys_on_the_peer_not_on_what_the_client_wrote() {
        // DSM did not append: the one entry may be the client's own, `X-Forwarded-For:
        // <forged>` passed on untouched
        let got = client_ip(&headers(&["198.51.100.66"]), peer(), 2);
        assert_eq!(got.key, "172.18.0.5");
        // The log line still counts the entries: 1 of 2 tells a hop is missing
        assert_eq!(got.forwarded_entries, 1);
        let got = client_ip(&headers(&["198.51.100.66, 192.168.1.27"]), peer(), 3);
        assert_eq!(got.key, "172.18.0.5");
        assert_eq!(got.forwarded_entries, 2);
        // Without a connection: `unknown`, one key for every such request
        assert_eq!(
            client_ip(&headers(&["198.51.100.66"]), None, 2).key,
            "unknown"
        );
    }

    #[test]
    fn an_entry_that_is_not_an_address_is_never_the_key() {
        for forged in ["not-an-ip", "203.0.113.7:4444", "[2001:db8::1]", "unknown"] {
            let h = headers(&[&format!("{forged}, 192.168.1.25")]);
            let got = client_ip(&h, peer(), 2);
            assert_eq!(got.key, "172.18.0.5", "{forged}");
            assert_eq!(got.forwarded_entries, 2);
        }
        // Left of the client's entry, anything changes nothing
        let h = headers(&["garbage, 203.0.113.7, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).key, "203.0.113.7");
    }

    #[test]
    fn an_ipv6_client_is_keyed_by_its_64() {
        let h = headers(&["2001:db8:1:2::aa, 192.168.1.25"]);
        let first = client_ip(&h, peer(), 2).key;
        assert_eq!(first, "2001:db8:1:2::/64");
        let h = headers(&["2001:db8:1:2:ffff:ffff:ffff:ffff, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).key, first);
        // The next /64 is another client
        assert_ne!(key("2001:db8:1:3::aa"), first);
        // The peer is keyed the same way
        let v6_peer = Some("[2001:db8:1:2::bb]:41000".parse().unwrap());
        assert_eq!(client_ip(&HeaderMap::new(), v6_peer, 2).key, first);
    }

    #[test]
    fn an_ipv4_client_is_keyed_by_its_whole_address() {
        assert_eq!(key("203.0.113.7"), "203.0.113.7");
        assert_ne!(key("203.0.113.7"), key("203.0.113.8"));
        // IPv4-mapped IPv6, in the header or as the peer of a dual-stack socket
        assert_eq!(key("::ffff:203.0.113.7"), "203.0.113.7");
        let h = headers(&["::ffff:203.0.113.7, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).key, "203.0.113.7");
        let mapped_peer = Some("[::ffff:172.18.0.5]:41000".parse().unwrap());
        assert_eq!(
            client_ip(&HeaderMap::new(), mapped_peer, 2).key,
            "172.18.0.5"
        );
    }

    #[test]
    fn without_the_header_or_trust_the_peer_answers() {
        assert_eq!(client_ip(&HeaderMap::new(), peer(), 2).key, "172.18.0.5");
        let got = client_ip(&headers(&["203.0.113.7, 192.168.1.25"]), peer(), 0);
        assert_eq!(got.key, "172.18.0.5");
        assert_eq!(got.forwarded_entries, 2);
        assert_eq!(client_ip(&HeaderMap::new(), None, 2).key, "unknown");
        // With `TRUSTED_PROXY_HOPS=1` (nginx alone in front, set by hand; the default is
        // 2 everywhere), nginx's entry names the client
        assert_eq!(
            client_ip(&headers(&["203.0.113.7"]), peer(), 1).key,
            "203.0.113.7"
        );
    }

    #[test]
    fn the_hop_count_defaults_to_two() {
        assert_eq!(trusted_proxy_hops_from(None), 2);
        assert_eq!(trusted_proxy_hops_from(Some("x".into())), 2);
        assert_eq!(trusted_proxy_hops_from(Some(" 1 ".into())), 1);
        assert_eq!(trusted_proxy_hops_from(Some("0".into())), 0);
    }
}
