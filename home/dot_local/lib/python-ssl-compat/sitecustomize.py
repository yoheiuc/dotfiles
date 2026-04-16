# sitecustomize.py — disable Python 3.13+ VERIFY_X509_STRICT
#
# Corporate CASB/proxies (Netskope, Zscaler, etc.) use MITM CA certificates
# that fail RFC 5280 strict validation added in Python 3.13.
# This restores Python 3.12-equivalent SSL behaviour.
#
# Loaded via PYTHONPATH set in ~/.config/zsh/env.zsh.
# To disable after certificate rotation: rm ~/.local/lib/python-ssl-compat/sitecustomize.py
import ssl

if hasattr(ssl, "VERIFY_X509_STRICT"):
    _orig_create_default_context = ssl.create_default_context

    def _patched_create_default_context(*args, **kwargs):
        ctx = _orig_create_default_context(*args, **kwargs)
        ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
        return ctx

    ssl.create_default_context = _patched_create_default_context
