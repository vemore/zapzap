import { describe, it, expect, afterEach } from 'vitest';
import { sseUrl } from '../sse';

describe('sseUrl', () => {
  afterEach(() => localStorage.removeItem('token'));

  it('carries the URL-encoded token of the signed-in user', () => {
    localStorage.setItem('token', 'x.y/z+w=');
    expect(sseUrl()).toBe(`${window.location.origin}/suscribeupdate?token=x.y%2Fz%2Bw%3D`);
  });

  it('is null without a token, so no stream opens', () => {
    expect(sseUrl()).toBeNull();
  });
});
