// The URL of the server-sent events stream, /suscribeupdate.
//
// The stream carries the signed-in user's token: the Rust backend delivers a party's
// events only to streams whose token names a player of that party, and tracks presence
// by it. EventSource cannot send an Authorization header, hence the query parameter.
// VITE_API_URL (dev) points at the backend; otherwise the stream is on the page's origin.
export function sseUrl() {
  const token = localStorage.getItem('token');
  if (!token) return null;
  const baseUrl = import.meta.env.VITE_API_URL?.replace('/api', '') || window.location.origin;
  return `${baseUrl}/suscribeupdate?token=${encodeURIComponent(token)}`;
}

export default sseUrl;
