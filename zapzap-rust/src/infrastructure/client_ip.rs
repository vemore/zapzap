//! The address of the client behind the proxies, for a per-client rate limit.
//!
//! In production a request crosses two proxies before the backend: the Synology DSM
//! reverse proxy (TLS), then the `zapzap-proxy` nginx (`nginx/nginx.conf`). Each appends
//! the address it was connected from to `X-Forwarded-For` (`$proxy_add_x_forwarded_for`):
//! DSM the client's, nginx DSM's. So the client is the entry `TRUSTED_PROXY_HOPS` (2) from
//! the right; whatever stands left of it was sent by the client and is not trusted.
//! nginx's `X-Real-IP` is DSM's address, the same for every client: not used.

use std::net::SocketAddr;

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

/// Where the client address came from, for the log line that checks the hop count
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientIp {
    pub ip: String,
    /// The entries `X-Forwarded-For` held (0 without the header)
    pub forwarded_entries: usize,
}

/// The client's address: the `X-Forwarded-For` entry `hops` from the right; the leftmost
/// one when the header holds fewer (a request that crossed fewer proxies, such as nginx
/// alone locally); the connection's peer without the header or with `hops` 0; else
/// `unknown` (the API tests, which have no connection)
pub fn client_ip(headers: &HeaderMap, peer: Option<SocketAddr>, hops: usize) -> ClientIp {
    let entries: Vec<&str> = headers
        .get_all("x-forwarded-for")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .collect();
    let forwarded = if hops == 0 || entries.is_empty() {
        None
    } else {
        Some(entries[entries.len().saturating_sub(hops)])
    };
    let ip = forwarded
        .map(str::to_string)
        .or_else(|| peer.map(|p| p.ip().to_string()))
        .unwrap_or_else(|| "unknown".to_string());
    ClientIp {
        ip,
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

    #[test]
    fn behind_dsm_and_nginx_the_client_is_second_from_the_right() {
        let got = client_ip(&headers(&["203.0.113.7, 192.168.1.25"]), peer(), 2);
        assert_eq!(got.ip, "203.0.113.7");
        assert_eq!(got.forwarded_entries, 2);
    }

    #[test]
    fn what_the_client_sent_itself_is_not_trusted() {
        // The client sent `X-Forwarded-For: 1.2.3.4`; DSM and nginx appended theirs
        let h = headers(&["1.2.3.4, 203.0.113.7, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).ip, "203.0.113.7");
        // Several header lines read as one list
        let h = headers(&["1.2.3.4", "203.0.113.7, 192.168.1.25"]);
        assert_eq!(client_ip(&h, peer(), 2).ip, "203.0.113.7");
    }

    #[test]
    fn fewer_entries_than_hops_take_the_leftmost() {
        assert_eq!(
            client_ip(&headers(&["203.0.113.7"]), peer(), 2).ip,
            "203.0.113.7"
        );
    }

    #[test]
    fn without_the_header_or_trust_the_peer_answers() {
        assert_eq!(client_ip(&HeaderMap::new(), peer(), 2).ip, "172.18.0.5");
        assert_eq!(
            client_ip(&headers(&["203.0.113.7"]), peer(), 0).ip,
            "172.18.0.5"
        );
        assert_eq!(client_ip(&HeaderMap::new(), None, 2).ip, "unknown");
    }

    #[test]
    fn the_hop_count_defaults_to_two() {
        assert_eq!(trusted_proxy_hops_from(None), 2);
        assert_eq!(trusted_proxy_hops_from(Some("x".into())), 2);
        assert_eq!(trusted_proxy_hops_from(Some(" 1 ".into())), 1);
        assert_eq!(trusted_proxy_hops_from(Some("0".into())), 0);
    }
}
