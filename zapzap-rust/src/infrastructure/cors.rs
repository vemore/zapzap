//! Which browser origins the API answers cross-origin (`ALLOWED_ORIGINS`).
//!
//! Both production clients are same-origin (the React client on `/`, the Flutter PWA under
//! `/app/`), and the Android app is no browser: it sends no `Origin`. CORS only decides
//! whether a page of *another* site may read the answers, so production names its own
//! origin and nothing else (`docker-compose.prod.yml`). Unset, every origin is answered, as
//! a development server needs (the Flutter web client on its own port).

use axum::http::HeaderValue;
use tower_http::cors::{AllowHeaders, AllowOrigin, Any, CorsLayer};

/// The origins CORS grants, from `ALLOWED_ORIGINS`
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AllowedOrigins {
    /// `ALLOWED_ORIGINS` unset or blank: every origin (development)
    Unset,
    /// `ALLOWED_ORIGINS` holds a `*`, alone or among origins: every origin
    Wildcard,
    /// Only these origins, as a browser sends them (`https://host[:port]`, lowercase)
    List(Vec<HeaderValue>),
}

impl AllowedOrigins {
    /// From the environment. A malformed entry is an error: the server refuses to start
    /// rather than grant something other than what was written.
    pub fn from_env() -> anyhow::Result<Self> {
        Self::parse(std::env::var("ALLOWED_ORIGINS").ok().as_deref())
    }

    /// From the value of `ALLOWED_ORIGINS`: origins separated by commas. Each is trimmed,
    /// lowercased and loses a trailing `/`, since a browser sends `https://host[:port]` and
    /// an entry written otherwise would never match. `*` anywhere means every origin.
    pub fn parse(value: Option<&str>) -> anyhow::Result<Self> {
        let entries: Vec<&str> = value
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|entry| !entry.is_empty())
            .collect();
        if entries.is_empty() {
            return Ok(Self::Unset);
        }
        if entries.contains(&"*") {
            return Ok(Self::Wildcard);
        }
        let mut origins = Vec::with_capacity(entries.len());
        for entry in entries {
            let origin = entry.trim_end_matches('/').to_ascii_lowercase();
            let host = origin
                .strip_prefix("https://")
                .or_else(|| origin.strip_prefix("http://"));
            let valid = host.is_some_and(|host| {
                !host.is_empty()
                    && !host.contains(['/', '?', '#', '@'])
                    && !host.chars().any(char::is_whitespace)
            });
            if !valid {
                anyhow::bail!(
                    "ALLOWED_ORIGINS: {entry:?} is not an origin: write scheme://host[:port], \
                     e.g. https://zapzap.example, several separated by commas"
                );
            }
            let origin = HeaderValue::from_str(&origin)
                .map_err(|_| anyhow::anyhow!("ALLOWED_ORIGINS: {entry:?} is not an origin"))?;
            if !origins.contains(&origin) {
                origins.push(origin);
            }
        }
        Ok(Self::List(origins))
    }

    /// Says at startup which of the two behaviours applies
    pub fn log(&self) {
        match self {
            Self::Unset => tracing::warn!(
                "ALLOWED_ORIGINS not set: CORS answers every origin (development only; \
                 production sets it in docker-compose.prod.yml)"
            ),
            Self::Wildcard => tracing::warn!(
                "ALLOWED_ORIGINS holds a wildcard (*): CORS answers every origin, whatever \
                 else it lists"
            ),
            Self::List(origins) => tracing::info!(
                "CORS answers only the origins of ALLOWED_ORIGINS: {}",
                origins
                    .iter()
                    .map(|o| o.to_str().unwrap_or_default())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        }
    }

    /// The layer: any method, and the request headers a preflight asks for, for the origins
    /// granted. The headers are mirrored rather than `*`, which by the Fetch standard never
    /// covers `Authorization`: a strict browser would refuse every authenticated call. A
    /// request from another origin, or with none, is still served: the browser alone
    /// withholds the answer from a page it did not grant.
    pub fn layer(&self) -> CorsLayer {
        let origin = match self {
            Self::Unset | Self::Wildcard => AllowOrigin::any(),
            Self::List(origins) => AllowOrigin::list(origins.iter().cloned()),
        };
        CorsLayer::new()
            .allow_origin(origin)
            .allow_methods(Any)
            .allow_headers(AllowHeaders::mirror_request())
            .expose_headers(Any)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list(origins: &[&str]) -> AllowedOrigins {
        AllowedOrigins::List(
            origins
                .iter()
                .map(|o| HeaderValue::from_str(o).unwrap())
                .collect(),
        )
    }

    #[test]
    fn unset_or_blank_answers_every_origin() {
        for value in [None, Some(""), Some(" , ")] {
            assert_eq!(
                AllowedOrigins::parse(value).unwrap(),
                AllowedOrigins::Unset,
                "{value:?}"
            );
        }
    }

    #[test]
    fn a_star_anywhere_is_a_wildcard_not_unset() {
        for value in ["*", "https://a.example,*", " * , https://a.example"] {
            assert_eq!(
                AllowedOrigins::parse(Some(value)).unwrap(),
                AllowedOrigins::Wildcard,
                "{value}"
            );
        }
    }

    #[test]
    fn a_list_is_split_trimmed_lowercased_and_deduplicated() {
        assert_eq!(
            AllowedOrigins::parse(Some(
                " https://A.example/ ,http://localhost:5173,https://a.example"
            ))
            .unwrap(),
            list(&["https://a.example", "http://localhost:5173"])
        );
    }

    #[test]
    fn an_entry_that_is_not_an_origin_is_refused() {
        for bad in [
            "a.example",
            "ftp://a.example",
            "https://",
            "https://a.example/app",
            "https://a.example?x=1",
            "https://user@a.example",
            "https://a .example",
        ] {
            let err = AllowedOrigins::parse(Some(bad)).unwrap_err().to_string();
            assert!(err.contains("ALLOWED_ORIGINS"), "{bad}: {err}");
        }
    }
}
