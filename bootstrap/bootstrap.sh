#!/usr/bin/env bash
#
# bootstrap.sh — build/refresh the local Python virtualenv this role runs
# from. Designed to live on a portable USB stick: the venv is a compiled
# artifact tied to whatever machine it's built on, so this script is
# idempotent and safe to re-run every time the stick is plugged into a
# *different* machine — it rebuilds only when the venv is missing or on the
# wrong Python version, otherwise it's a fast no-op.
#
set -euo pipefail

ROLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_VERSION="3.13.5"
VENV_DIR="${ROLE_DIR}/.venv"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: 'uv' is required but not found on PATH." >&2
    echo "       install it: https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

venv_is_current() {
    [ -x "${VENV_DIR}/bin/python" ] && \
        "${VENV_DIR}/bin/python" -c \
            "import sys; sys.exit(0 if sys.version.startswith('${PYTHON_VERSION}') else 1)" \
            >/dev/null 2>&1
}

if venv_is_current; then
    echo "[bootstrap] venv already at Python ${PYTHON_VERSION} — skipping rebuild."
else
    echo "[bootstrap] installing Python ${PYTHON_VERSION} via uv..."
    uv python install "${PYTHON_VERSION}"

    echo "[bootstrap] creating venv at ${VENV_DIR}..."
    rm -rf "${VENV_DIR}"
    uv venv --python "${PYTHON_VERSION}" "${VENV_DIR}"

    echo "[bootstrap] installing Python requirements..."
    uv pip install --python "${VENV_DIR}/bin/python" -r "${ROLE_DIR}/bootstrap/requirements.txt"

    echo "[bootstrap] installing Ansible collections..."
    "${VENV_DIR}/bin/ansible-galaxy" collection install -r "${ROLE_DIR}/bootstrap/requirements.yml"
fi

echo "[bootstrap] ready. Activate with:"
echo "  source ${VENV_DIR}/bin/activate"
