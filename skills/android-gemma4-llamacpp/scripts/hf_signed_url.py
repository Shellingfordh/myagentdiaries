#!/usr/bin/env python3
import argparse
import sys
import urllib.error
import urllib.request


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, hdrs, newurl):
        return None


def resolve_signed_url(url: str) -> str:
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        opener.open(url, timeout=30)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            loc = e.headers.get("Location")
            if not loc:
                raise RuntimeError("Redirect without Location header")
            return loc
        raise
    raise RuntimeError("Expected redirect, got success response")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="HuggingFace repo, e.g. HauhauCS/...")
    ap.add_argument("--file", required=True, help="Repo filename, e.g. model.gguf")
    args = ap.parse_args()

    resolve_url = (
        f"https://huggingface.co/{args.repo}/resolve/main/{args.file}?download=true"
    )
    signed = resolve_signed_url(resolve_url)
    sys.stdout.write(signed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

